"""Master-password login + server-side device approval (DECISIONS.md #54).

Replaces the old setup-code / claim-role / pairing onboarding entirely:

1. Any phone types the ONE shared master password.
2. A phone the server already knows (approved before, matched by its
   stable device_uuid) gets tokens + the vault key straight away.
3. An unknown phone becomes a pending DeviceRequest, shown in the admin
   panel with a short code. The phone polls /auth/master/status.
4. The admin approves it (picking husband/wife). The phone's next poll
   gets tokens + the vault key, and from then on step 2 applies.
"""
import base64
import secrets
import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse
from app.models.common import utcnow
from app.models.device_request import DeviceRequest
from app.models.misc import AppSetting
from app.models.setup import VaultKey
from app.models.user import Spouse, Device, RoleEnum
from app.services.rate_limit import rate_limit
from app.services.security import hash_secret, verify_secret, encrypt_at_rest, decrypt_at_rest

router = APIRouter(prefix="/auth/master", tags=["auth-master"])

MASTER_PASSWORD_KEY = "master_password_hash"
_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # no 0/O/1/I/L confusion


async def get_master_hash(db: AsyncSession) -> str | None:
    row = await db.get(AppSetting, MASTER_PASSWORD_KEY)
    return row.value if row else None


async def set_master_hash(db: AsyncSession, hashed: str) -> None:
    row = await db.get(AppSetting, MASTER_PASSWORD_KEY)
    if row:
        row.value = hashed
    else:
        db.add(AppSetting(key=MASTER_PASSWORD_KEY, value=hashed))
    await db.commit()


async def get_vmk_b64(db: AsyncSession) -> str | None:
    result = await db.execute(select(VaultKey))
    key = result.scalars().first()
    if key is None:
        return None
    return base64.b64encode(decrypt_at_rest(key.vmk_encrypted)).decode()


async def get_or_create_spouse(db: AsyncSession, role: str) -> Spouse:
    result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(role)))
    spouse = result.scalar_one_or_none()
    if spouse is None:
        # password_hash is a legacy per-role column; the master password is
        # what's actually checked now. Store the master hash so the column
        # stays meaningful (and non-null).
        spouse = Spouse(role=RoleEnum(role), password_hash=await get_master_hash(db) or "")
        db.add(spouse)
        await db.flush()
    return spouse


async def ensure_vault_key_if_fresh(db: AsyncSession) -> None:
    """A brand-new deployment (no phones at all yet) has no vault key --
    generate it. If phones already exist but the server has no key, we
    must NOT invent one (it wouldn't match their content); an existing
    logged-in phone uploads its real key instead (POST /vault-key)."""
    from app.services.security import generate_vmk
    if (await db.execute(select(VaultKey))).scalars().first() is not None:
        return
    if (await db.execute(select(Device.id).limit(1))).first() is not None:
        return
    db.add(VaultKey(vmk_encrypted=encrypt_at_rest(generate_vmk())))
    await db.flush()


def _new_code() -> str:
    raw = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(4))
    return f"{raw[:2]}-{raw[2:]}"


class MasterLoginRequest(BaseModel):
    password: str
    device_uuid: str
    device_name: str


class MasterStatusRequest(BaseModel):
    request_id: uuid.UUID
    poll_token: str


async def _full_login_payload(db: AsyncSession, spouse: Spouse, device_name: str, device_uuid: str, device: Device | None) -> dict:
    from app.routers.auth import _issue_full_login
    data = await _issue_full_login(db, spouse, device_name, device_uuid, existing_device=device)
    return {
        "status": "approved",
        "access_token": data["access_token"],
        "refresh_token": data["refresh_token"],
        "spouse_id": str(data["spouse_id"]),
        "device_id": str(data["device_id"]),
        "role": data["role"],
        "vmk_b64": await get_vmk_b64(db),
    }


@router.post("/login", dependencies=[Depends(rate_limit("master_login", max_attempts=10, window_seconds=300))])
async def master_login(payload: MasterLoginRequest, db: AsyncSession = Depends(get_db)):
    master_hash = await get_master_hash(db)
    if master_hash is None:
        raise HTTPException(status_code=409, detail="মাস্টার পাসওয়ার্ড এখনো সেট করা হয়নি। অ্যাডমিন প্যানেল থেকে সেট করুন।")
    if not payload.device_uuid or len(payload.device_uuid) > 64:
        raise HTTPException(status_code=400, detail="Invalid device id")
    if not verify_secret(payload.password, master_hash):
        raise HTTPException(status_code=401, detail="পাসওয়ার্ড সঠিক নয়")

    # Already-approved phone: straight in.
    result = await db.execute(select(Device).where(Device.device_uuid == payload.device_uuid))
    device = result.scalars().first()
    if device is not None:
        spouse = await db.get(Spouse, device.spouse_id)
        return await _full_login_payload(db, spouse, payload.device_name, payload.device_uuid, device)

    # Unknown phone: (re)use its pending request, or open a new one. A
    # previously rejected phone that tries again gets a fresh request --
    # the admin can simply reject again.
    result = await db.execute(
        select(DeviceRequest).where(DeviceRequest.device_uuid == payload.device_uuid).order_by(DeviceRequest.created_at.desc())
    )
    req = result.scalars().first()
    poll_token = secrets.token_urlsafe(32)
    if req is None or req.status == "rejected":
        if req is not None:
            await db.delete(req)
        req = DeviceRequest(
            device_uuid=payload.device_uuid,
            device_name=payload.device_name[:120],
            code=_new_code(),
            poll_secret_hash=hash_secret(poll_token),
            status="pending",
        )
        db.add(req)
    else:
        # Same phone asking again (app restarted while waiting) -- keep the
        # same code so the admin isn't confused, rotate the poll secret.
        req.poll_secret_hash = hash_secret(poll_token)
        req.device_name = payload.device_name[:120]
    await db.commit()
    await db.refresh(req)
    return {"status": req.status, "request_id": str(req.id), "code": req.code, "poll_token": poll_token}


@router.post("/status", dependencies=[Depends(rate_limit("master_status", max_attempts=120, window_seconds=300))])
async def master_status(payload: MasterStatusRequest, db: AsyncSession = Depends(get_db)):
    req = await db.get(DeviceRequest, payload.request_id)
    if req is None or not verify_secret(payload.poll_token, req.poll_secret_hash):
        raise HTTPException(status_code=404, detail="অনুরোধটি পাওয়া যায়নি। আবার পাসওয়ার্ড দিন।")
    if req.status == "pending":
        return {"status": "pending", "code": req.code}
    if req.status == "rejected":
        return {"status": "rejected"}

    # Approved: mint the real Device + tokens exactly once, then the
    # request has served its purpose.
    await ensure_vault_key_if_fresh(db)
    spouse = await get_or_create_spouse(db, req.role)
    device_name, device_uuid = req.device_name, req.device_uuid
    await db.delete(req)
    await db.flush()
    return await _full_login_payload(db, spouse, device_name, device_uuid, None)


class VaultKeyEscrow(BaseModel):
    vmk_b64: str


@router.post("/vault-key")
async def escrow_vault_key(payload: VaultKeyEscrow, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Deployments whose vault key was never persisted server-side (both
    roles claimed before DECISIONS.md #22) can't hand a key to newly
    approved phones. An already-working, logged-in phone fills that gap
    by uploading the key it already has. Never overwrites an existing key."""
    result = await db.execute(select(VaultKey))
    if result.scalars().first() is not None:
        return {"stored": False, "reason": "exists"}
    try:
        raw = base64.b64decode(payload.vmk_b64)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid key")
    if len(raw) != 32:
        raise HTTPException(status_code=400, detail="Invalid key length")
    db.add(VaultKey(vmk_encrypted=encrypt_at_rest(raw)))
    await db.commit()
    return {"stored": True}


@router.get("/vault-key/present")
async def vault_key_present(spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(VaultKey))
    return {"present": result.scalars().first() is not None}


async def resolve_request(db: AsyncSession, request_id: uuid.UUID, approve: bool, role: str | None) -> DeviceRequest:
    req = await db.get(DeviceRequest, request_id)
    if req is None:
        raise HTTPException(status_code=404, detail="Request not found")
    if req.status != "pending":
        raise HTTPException(status_code=409, detail="Already resolved")
    if approve:
        if role not in ("husband", "wife"):
            raise HTTPException(status_code=400, detail="role must be husband or wife")
        req.status = "approved"
        req.role = role
    else:
        req.status = "rejected"
    req.resolved_at = utcnow()
    await db.commit()
    return req
