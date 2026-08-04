import base64
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.deps import get_current_spouse
from app.models.setup import SetupCode
from app.models.user import Spouse, Device, RoleEnum
from app.models.reset_session import PasswordResetSession
from app.models.audit import AuditLogEntry
from app.schemas.auth import (
    ClaimRoleRequest, ClaimRoleResponse,
    TotpSetupConfirmRequest,
    LoginPasswordRequest, LoginPasswordResponse,
    LoginTotpRequest, LoginTotpResponse,
    LoginFaceRequest, LoginFaceResponse,
    RefreshRequest, RefreshResponse,
    FaceEnrollRequest,
    DuressSetRequest,
    PasswordResetInitiateRequest, PasswordResetVerifyRequest, PasswordResetCompleteRequest,
    SpouseOut,
)
from app.services.security import (
    hash_secret, verify_secret, create_access_token, create_refresh_token,
    decode_token_safe, TokenError,
)
from app.services.face_verify import face_verify_service
from app.services import totp as totp_service

router = APIRouter(prefix="/auth", tags=["auth"])
settings = get_settings()


def _decode_face_image(face_image_b64: str) -> bytes:
    try:
        return base64.b64decode(face_image_b64)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid face_image_b64")


def _create_challenge_token(spouse_id: str, role: str, device_name: str, token_type: str, minutes: int = 5) -> str:
    from jose import jwt
    expire = datetime.now(timezone.utc) + timedelta(minutes=minutes)
    return jwt.encode(
        {"sub": spouse_id, "role": role, "device_name": device_name, "exp": expire, "type": token_type},
        settings.jwt_secret, algorithm=settings.jwt_algorithm,
    )


async def _issue_full_login(db: AsyncSession, spouse: Spouse, device_name: str) -> dict:
    refresh_token = create_refresh_token(str(spouse.id), device_id=str(uuid.uuid4()))
    device = Device(
        spouse_id=spouse.id,
        device_name=device_name,
        refresh_token_hash=hash_secret(refresh_token),
    )
    db.add(device)
    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.login", target_type="spouse", target_id=spouse.id))
    await db.commit()

    access_token = create_access_token(str(spouse.id), spouse.role.value)
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "spouse_id": spouse.id,
        "role": spouse.role.value,
    }


@router.post("/setup/claim", response_model=ClaimRoleResponse)
async def claim_role(payload: ClaimRoleRequest, db: AsyncSession = Depends(get_db)):
    if payload.role not in ("husband", "wife"):
        raise HTTPException(status_code=400, detail="role must be 'husband' or 'wife'")

    result = await db.execute(select(SetupCode).where(SetupCode.token == payload.token))
    code = result.scalar_one_or_none()
    if code is None:
        raise HTTPException(status_code=404, detail="Setup code not found")
    if code.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=410, detail="Setup code expired")

    already_claimed = code.claimed_husband if payload.role == "husband" else code.claimed_wife
    if already_claimed:
        raise HTTPException(status_code=409, detail="This role has already been claimed with this code")

    existing = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(payload.role)))
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(status_code=409, detail=f"{payload.role} already registered on this deployment")

    from app.services.security import decrypt_at_rest
    vmk = decrypt_at_rest(code.vmk_encrypted)

    totp_secret = totp_service.generate_secret()
    spouse = Spouse(role=RoleEnum(payload.role), password_hash=hash_secret(payload.password), totp_secret=totp_secret)
    db.add(spouse)
    await db.flush()

    refresh_token = create_refresh_token(str(spouse.id), device_id=str(uuid.uuid4()))
    device = Device(
        spouse_id=spouse.id,
        device_name=payload.device_name,
        refresh_token_hash=hash_secret(refresh_token),
    )
    db.add(device)

    if payload.role == "husband":
        code.claimed_husband = True
    else:
        code.claimed_wife = True

    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.claim_role", target_type="spouse", target_id=spouse.id, detail=payload.role))

    fully_claimed = code.claimed_husband and code.claimed_wife
    if fully_claimed:
        await db.delete(code)

    await db.commit()

    access_token = create_access_token(str(spouse.id), payload.role)
    return ClaimRoleResponse(
        spouse_id=spouse.id,
        role=payload.role,
        access_token=access_token,
        refresh_token=refresh_token,
        vmk_b64=base64.b64encode(vmk).decode(),
        server=f"https://{settings.domain}",
        totp_secret=totp_secret,
        totp_provisioning_uri=totp_service.provisioning_uri(totp_secret, f"{payload.role}@couplevault"),
    )


@router.get("/me", response_model=SpouseOut)
async def get_me(spouse: Spouse = Depends(get_current_spouse)):
    return SpouseOut.from_spouse(spouse)


@router.post("/totp/setup-confirm")
async def totp_setup_confirm(payload: TotpSetupConfirmRequest, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Proves the spouse actually saved the TOTP secret into an authenticator
    app before we start requiring it at every login."""
    if spouse.totp_secret is None:
        raise HTTPException(status_code=409, detail="No TOTP secret on file for this spouse")
    if not totp_service.verify_code(spouse.totp_secret, payload.code):
        raise HTTPException(status_code=401, detail="Invalid authenticator code")
    spouse.totp_confirmed = True
    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.totp_setup_confirm", target_type="spouse", target_id=spouse.id))
    await db.commit()
    return {"totp_confirmed": True}


@router.post("/face/enroll")
async def enroll_face(payload: FaceEnrollRequest, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    image = _decode_face_image(payload.face_image_b64)
    subject = str(spouse.id)
    await face_verify_service.enroll(subject, image)
    spouse.compreface_subject = subject
    spouse.face_enrolled = True
    spouse.face_verification_enabled = True
    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.face_enroll", target_type="spouse", target_id=spouse.id))
    await db.commit()
    return {"face_enrolled": True, "face_verification_enabled": True}


@router.post("/face/disable")
async def disable_face(spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    spouse.face_verification_enabled = False
    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.face_disable", target_type="spouse", target_id=spouse.id))
    await db.commit()
    return {"face_verification_enabled": False}


@router.post("/face/enable")
async def enable_face(spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Re-enable a previously-enrolled face without re-registering. If the
    spouse never enrolled at all, the client should call /auth/face/enroll
    instead (which enrolls AND enables in one step)."""
    if not spouse.face_enrolled:
        raise HTTPException(status_code=409, detail="Face has not been registered yet -- enroll first")
    spouse.face_verification_enabled = True
    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.face_enable", target_type="spouse", target_id=spouse.id))
    await db.commit()
    return {"face_verification_enabled": True}


@router.post("/login/password", response_model=LoginPasswordResponse)
async def login_password(payload: LoginPasswordRequest, db: AsyncSession = Depends(get_db)):
    if payload.role not in ("husband", "wife"):
        raise HTTPException(status_code=400, detail="Invalid role")
    result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(payload.role)))
    spouse = result.scalar_one_or_none()
    if spouse is None or not verify_secret(payload.password, spouse.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not spouse.totp_confirmed:
        raise HTTPException(status_code=409, detail="Authenticator app not set up yet for this spouse")

    challenge = _create_challenge_token(str(spouse.id), payload.role, payload.device_name, "totp_challenge")
    return LoginPasswordResponse(challenge_token=challenge)


@router.post("/login/totp", response_model=LoginTotpResponse)
async def login_totp(payload: LoginTotpRequest, db: AsyncSession = Depends(get_db)):
    try:
        claims = decode_token_safe(payload.challenge_token)
    except TokenError:
        raise HTTPException(status_code=401, detail="Invalid or expired challenge token")
    if claims.get("type") != "totp_challenge":
        raise HTTPException(status_code=401, detail="Invalid challenge token")

    spouse_id = uuid.UUID(claims["sub"])
    result = await db.execute(select(Spouse).where(Spouse.id == spouse_id))
    spouse = result.scalar_one_or_none()
    if spouse is None or spouse.totp_secret is None:
        raise HTTPException(status_code=404, detail="Spouse not found")

    if not totp_service.verify_code(spouse.totp_secret, payload.code):
        db.add(AuditLogEntry(actor_id=spouse.id, action="auth.totp_verify_failed", target_type="spouse", target_id=spouse.id))
        await db.commit()
        raise HTTPException(status_code=401, detail="Invalid authenticator code")

    device_name = claims.get("device_name", "device")

    if spouse.face_verification_enabled:
        face_challenge = _create_challenge_token(str(spouse.id), spouse.role.value, device_name, "face_challenge")
        db.add(AuditLogEntry(actor_id=spouse.id, action="auth.totp_verify_ok", target_type="spouse", target_id=spouse.id))
        await db.commit()
        return LoginTotpResponse(requires_face=True, face_challenge_token=face_challenge)

    result_data = await _issue_full_login(db, spouse, device_name)
    return LoginTotpResponse(requires_face=False, **result_data)


@router.post("/login/face", response_model=LoginFaceResponse)
async def login_face(payload: LoginFaceRequest, db: AsyncSession = Depends(get_db)):
    try:
        claims = decode_token_safe(payload.challenge_token)
    except TokenError:
        raise HTTPException(status_code=401, detail="Invalid or expired challenge token")
    if claims.get("type") != "face_challenge":
        raise HTTPException(status_code=401, detail="Invalid challenge token")

    spouse_id = uuid.UUID(claims["sub"])
    result = await db.execute(select(Spouse).where(Spouse.id == spouse_id))
    spouse = result.scalar_one_or_none()
    if spouse is None:
        raise HTTPException(status_code=404, detail="Spouse not found")

    image = _decode_face_image(payload.face_image_b64)
    matched = await face_verify_service.verify(str(spouse.id), image)
    if not matched:
        db.add(AuditLogEntry(actor_id=spouse.id, action="auth.face_verify_failed", target_type="spouse", target_id=spouse.id))
        await db.commit()
        raise HTTPException(status_code=401, detail="Face verification failed")

    result_data = await _issue_full_login(db, spouse, claims.get("device_name", "device"))
    return LoginFaceResponse(**result_data)


@router.post("/refresh", response_model=RefreshResponse)
async def refresh_token_endpoint(payload: RefreshRequest, db: AsyncSession = Depends(get_db)):
    try:
        claims = decode_token_safe(payload.refresh_token)
    except TokenError:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")
    if claims.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid token type")

    spouse_id = uuid.UUID(claims["sub"])
    result = await db.execute(select(Spouse).where(Spouse.id == spouse_id))
    spouse = result.scalar_one_or_none()
    if spouse is None:
        raise HTTPException(status_code=401, detail="Spouse not found")

    access_token = create_access_token(str(spouse.id), spouse.role.value)
    return RefreshResponse(access_token=access_token)


@router.post("/duress/set")
async def set_duress_pin(payload: DuressSetRequest, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    if len(payload.pin) < 4:
        raise HTTPException(status_code=400, detail="PIN must be at least 4 digits")
    spouse.duress_pin_hash = hash_secret(payload.pin)
    await db.commit()
    return {"ok": True}


@router.post("/password-reset/initiate")
async def password_reset_initiate(payload: PasswordResetInitiateRequest, db: AsyncSession = Depends(get_db)):
    if payload.role not in ("husband", "wife"):
        raise HTTPException(status_code=400, detail="Invalid role")
    session = PasswordResetSession(
        target_role=payload.role,
        reset_token=secrets.token_urlsafe(24),
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
    )
    db.add(session)
    await db.commit()
    return {"reset_token": session.reset_token, "expires_at": session.expires_at}


@router.post("/password-reset/verify")
async def password_reset_verify(payload: PasswordResetVerifyRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PasswordResetSession).where(PasswordResetSession.reset_token == payload.reset_token))
    session = result.scalar_one_or_none()
    if session is None or session.used or session.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=404, detail="Reset session not found or expired")

    spouse_result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(payload.role)))
    spouse = spouse_result.scalar_one_or_none()
    if spouse is None or spouse.totp_secret is None:
        raise HTTPException(status_code=404, detail="Spouse not found")

    if not totp_service.verify_code(spouse.totp_secret, payload.code):
        raise HTTPException(status_code=401, detail="Invalid authenticator code")

    now = datetime.now(timezone.utc)
    if payload.role == "husband":
        session.husband_verified_at = now
    else:
        session.wife_verified_at = now
    await db.commit()
    return {"husband_verified": session.husband_verified_at is not None, "wife_verified": session.wife_verified_at is not None}


@router.post("/password-reset/complete")
async def password_reset_complete(payload: PasswordResetCompleteRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PasswordResetSession).where(PasswordResetSession.reset_token == payload.reset_token))
    session = result.scalar_one_or_none()
    if session is None or session.used or session.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=404, detail="Reset session not found or expired")
    if session.husband_verified_at is None or session.wife_verified_at is None:
        raise HTTPException(status_code=409, detail="Both spouses must pass authenticator verification first")

    spouse_result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(session.target_role)))
    spouse = spouse_result.scalar_one_or_none()
    if spouse is None:
        raise HTTPException(status_code=404, detail="Target spouse not found")

    spouse.password_hash = hash_secret(payload.new_password)
    session.used = True
    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.password_reset", target_type="spouse", target_id=spouse.id))
    await db.commit()
    return {"ok": True}
