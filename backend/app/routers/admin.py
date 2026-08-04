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
from app.models.setup import SetupCode
from app.models.user import Spouse
from app.services.admin_auth import (
    require_admin, get_admin_password_hash, set_admin_password_hash, create_admin_session_token,
)
from app.services.security import hash_secret, verify_secret, generate_setup_token, generate_vmk, encrypt_at_rest

router = APIRouter(prefix="/admin", tags=["admin"])
settings = get_settings()
templates = Jinja2Templates(directory="admin_panel/templates")


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


@router.post("/api/login")
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


@router.post("/api/setup-codes", dependencies=[Depends(require_admin)])
async def create_setup_code(db: AsyncSession = Depends(get_db)):
    token = generate_setup_token()
    vmk = generate_vmk()
    code = SetupCode(
        token=token,
        vmk_encrypted=encrypt_at_rest(vmk),
        expires_at=datetime.now(timezone.utc) + timedelta(hours=settings.setup_code_ttl_hours),
    )
    db.add(code)
    await db.commit()

    payload = {
        "server": f"https://{settings.domain}",
        "code": token,
        "vmk": base64.b64encode(vmk).decode(),
    }
    qr_payload = base64.b64encode(json.dumps(payload).encode()).decode()

    img = qrcode.make(qr_payload)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    qr_png_b64 = base64.b64encode(buf.getvalue()).decode()

    return {
        "token": token,
        "server": payload["server"],
        "qr_payload": qr_payload,
        "qr_png_b64": qr_png_b64,
        "expires_at": code.expires_at,
    }


@router.get("/api/setup-codes", dependencies=[Depends(require_admin)])
async def list_setup_codes(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(SetupCode))
    codes = result.scalars().all()
    return [
        {
            "token": c.token,
            "claimed_husband": c.claimed_husband,
            "claimed_wife": c.claimed_wife,
            "expires_at": c.expires_at,
        }
        for c in codes
    ]
