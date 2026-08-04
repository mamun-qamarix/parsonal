import base64
import io
import json
from datetime import datetime, timedelta, timezone

import qrcode
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.models.setup import SetupCode, VaultKey
from app.models.user import Spouse
from app.services.admin_auth import (
    require_admin, get_admin_password_hash, set_admin_password_hash, create_admin_session_token,
)
from app.services.security import hash_secret, verify_secret, generate_setup_token, generate_vmk, encrypt_at_rest, decrypt_at_rest
from app.services.rate_limit import rate_limit

router = APIRouter(prefix="/admin", tags=["admin"])
settings = get_settings()
templates = Jinja2Templates(directory="admin_panel/templates")


async def _get_or_create_vmk(db: AsyncSession) -> bytes:
    """The deployment's Vault Master Key is generated exactly once and
    never changes again -- every setup code (however many times it's
    regenerated) must hand out this SAME key, or devices that claimed
    under different codes couldn't decrypt each other's content. See
    DECISIONS.md."""
    result = await db.execute(select(VaultKey))
    key = result.scalar_one_or_none()
    if key is not None:
        return decrypt_at_rest(key.vmk_encrypted)
    vmk = generate_vmk()
    db.add(VaultKey(vmk_encrypted=encrypt_at_rest(vmk)))
    await db.commit()
    return vmk


def _code_payload(code: SetupCode, vmk: bytes) -> dict:
    payload = {
        "server": f"https://{settings.domain}",
        "code": code.token,
        "vmk": base64.b64encode(vmk).decode(),
    }
    qr_payload = base64.b64encode(json.dumps(payload).encode()).decode()
    img = qrcode.make(qr_payload)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return {
        "exists": True,
        "token": code.token,
        "server": payload["server"],
        "qr_payload": qr_payload,
        "qr_png_b64": base64.b64encode(buf.getvalue()).decode(),
        "created_at": code.created_at,
    }


@router.get("", response_class=HTMLResponse)
async def admin_page(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@router.get("/api/status")
async def admin_status(db: AsyncSession = Depends(get_db)):
    admin_hash = await get_admin_password_hash(db)
    husband = await db.execute(select(Spouse).where(Spouse.role == "husband"))
    wife = await db.execute(select(Spouse).where(Spouse.role == "wife"))
    return {
        "admin_password_set": admin_hash is not None,
        "husband_registered": husband.scalar_one_or_none() is not None,
        "wife_registered": wife.scalar_one_or_none() is not None,
        "domain": settings.domain,
    }


@router.post("/api/first-run")
async def first_run(password: str, db: AsyncSession = Depends(get_db)):
    existing = await get_admin_password_hash(db)
    if existing is not None:
        raise HTTPException(status_code=409, detail="Admin password already set")
    if len(password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")
    await set_admin_password_hash(db, hash_secret(password))
    return {"ok": True}


@router.post("/api/login", dependencies=[Depends(rate_limit("admin_login", max_attempts=10, window_seconds=600))])
async def admin_login(password: str, response: Response, db: AsyncSession = Depends(get_db)):
    admin_hash = await get_admin_password_hash(db)
    if admin_hash is None or not verify_secret(password, admin_hash):
        raise HTTPException(status_code=401, detail="Invalid admin password")
    token = create_admin_session_token()
    response.set_cookie(
        "admin_session", token, httponly=True,
        secure=settings.environment == "production",
        samesite="lax", max_age=12 * 3600,
    )
    return {"ok": True}


@router.get("/api/setup-codes/current", dependencies=[Depends(require_admin)])
async def get_current_setup_code(db: AsyncSession = Depends(get_db)):
    """Setup codes are persistent now (see DECISIONS.md) -- this lets the
    admin panel re-display the same QR/text on every page load instead of
    it only ever being shown once at creation time."""
    result = await db.execute(select(SetupCode).order_by(SetupCode.created_at.desc()))
    code = result.scalars().first()
    if code is None:
        return {"exists": False}
    vmk = await _get_or_create_vmk(db)
    return _code_payload(code, vmk)


@router.post("/api/setup-codes", dependencies=[Depends(require_admin)])
async def create_setup_code(db: AsyncSession = Depends(get_db)):
    """Idempotent: if a code already exists, just returns it rather than
    creating a redundant second one -- use DELETE first to actually
    rotate the shareable token. The Vault Master Key always comes from
    the persistent singleton, so regenerating the token never changes it."""
    existing = await db.execute(select(SetupCode).order_by(SetupCode.created_at.desc()))
    code = existing.scalars().first()
    vmk = await _get_or_create_vmk(db)
    if code is None:
        code = SetupCode(
            token=generate_setup_token(),
            vmk_encrypted=encrypt_at_rest(vmk),
            expires_at=datetime.now(timezone.utc) + timedelta(days=3650),
        )
        db.add(code)
        await db.commit()
    return _code_payload(code, vmk)


@router.delete("/api/setup-codes/{token}", dependencies=[Depends(require_admin)])
async def delete_setup_code(token: str, db: AsyncSession = Depends(get_db)):
    """Invalidates this shareable token (e.g. it leaked, or you just want a
    fresh one) -- devices that already claimed a role are completely
    unaffected, since the Vault Master Key lives independently and a new
    code will still hand out the same one."""
    result = await db.execute(select(SetupCode).where(SetupCode.token == token))
    code = result.scalar_one_or_none()
    if code is None:
        raise HTTPException(status_code=404, detail="Setup code not found")
    await db.delete(code)
    await db.commit()
    return {"ok": True}
