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
    LoginPasswordRequest, LoginPasswordResponse,
    LoginFaceRequest, LoginFaceResponse,
    RefreshRequest, RefreshResponse,
    FaceEnrollRequest,
    DuressSetRequest,
    PasswordResetInitiateRequest, PasswordResetApproveRequest, PasswordResetStatusRequest, PasswordResetCompleteRequest,
    SpouseOut,
)
from app.services.security import (
    hash_secret, verify_secret, create_access_token, create_refresh_token,
    decode_token_safe, TokenError,
)
from app.services.face_verify import face_verify_service
from app.services.rate_limit import rate_limit

router = APIRouter(prefix="/auth", tags=["auth"])
settings = get_settings()


def _decode_face_image(face_image_b64: str) -> bytes:
    try:
        return base64.b64decode(face_image_b64)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid face_image_b64")


def _create_challenge_token(
    spouse_id: str, role: str, device_name: str, token_type: str, minutes: int = 5,
    device_uuid: str | None = None, device_id: str | None = None,
) -> str:
    from jose import jwt
    expire = datetime.now(timezone.utc) + timedelta(minutes=minutes)
    claims = {"sub": spouse_id, "role": role, "device_name": device_name, "exp": expire, "type": token_type}
    if device_uuid:
        claims["device_uuid"] = device_uuid
    if device_id:
        claims["device_id"] = str(device_id)
    return jwt.encode(claims, settings.jwt_secret, algorithm=settings.jwt_algorithm)


async def _find_device(db: AsyncSession, spouse_id, device_uuid: str | None) -> Device | None:
    if not device_uuid:
        return None
    result = await db.execute(select(Device).where(Device.spouse_id == spouse_id, Device.device_uuid == device_uuid))
    return result.scalar_one_or_none()


async def _issue_full_login(
    db: AsyncSession, spouse: Spouse, device_name: str, device_uuid: str | None = None, existing_device: Device | None = None,
) -> dict:
    # If this physical installation already has a Device row (matched by
    # its stable device_uuid, or passed in directly when already known),
    # reuse it instead of piling up a new row on every login -- otherwise
    # re-logging in repeatedly (token expiry, testing, logout/login cycles)
    # fills the Devices screen with duplicate entries for the same phone.
    # See DECISIONS.md #20.
    device = existing_device or await _find_device(db, spouse.id, device_uuid)

    if device is not None:
        device.device_name = device_name
        device.last_seen_at = datetime.now(timezone.utc)
    else:
        # The Device row must exist (and have its real id) *before* the
        # refresh token is minted, since the token embeds that id -- that's
        # what lets /auth/refresh reject a token whose Device has since
        # been deleted. See DECISIONS.md #16.
        device = Device(
            spouse_id=spouse.id,
            device_name=device_name,
            device_uuid=device_uuid,
            refresh_token_hash="",  # placeholder, replaced below once we know the token
        )
        db.add(device)
        await db.flush()

    refresh_token = create_refresh_token(str(spouse.id), device_id=str(device.id))
    device.refresh_token_hash = hash_secret(refresh_token)

    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.login", target_type="spouse", target_id=spouse.id))
    await db.commit()

    access_token = create_access_token(str(spouse.id), spouse.role.value, device_id=str(device.id))
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "spouse_id": spouse.id,
        "device_id": device.id,
        "role": spouse.role.value,
    }


@router.post("/setup/claim", response_model=ClaimRoleResponse, dependencies=[Depends(rate_limit("setup_claim", max_attempts=20, window_seconds=600))])
async def claim_role(payload: ClaimRoleRequest, db: AsyncSession = Depends(get_db)):
    if payload.role not in ("husband", "wife"):
        raise HTTPException(status_code=400, detail="role must be 'husband' or 'wife'")

    # Setup codes are persistent/reusable now, not single-use (see
    # DECISIONS.md) -- the only real gate on claiming is whether this role
    # already has a Spouse row, checked right below. A device using this
    # code for an already-claimed role gets a clean 409 here that the app
    # turns into a normal login instead of a dead end.
    result = await db.execute(select(SetupCode).where(SetupCode.token == payload.token))
    code = result.scalar_one_or_none()
    if code is None:
        raise HTTPException(status_code=404, detail="Setup code not found")

    existing = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(payload.role)))
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(status_code=409, detail=f"{payload.role} already registered on this deployment")

    from app.services.security import decrypt_at_rest
    vmk = decrypt_at_rest(code.vmk_encrypted)

    spouse = Spouse(role=RoleEnum(payload.role), password_hash=hash_secret(payload.password))
    db.add(spouse)
    await db.flush()

    device = Device(
        spouse_id=spouse.id,
        device_name=payload.device_name,
        device_uuid=payload.device_uuid,
        refresh_token_hash="",
    )
    db.add(device)
    await db.flush()

    refresh_token = create_refresh_token(str(spouse.id), device_id=str(device.id))
    device.refresh_token_hash = hash_secret(refresh_token)

    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.claim_role", target_type="spouse", target_id=spouse.id, detail=payload.role))
    await db.commit()

    access_token = create_access_token(str(spouse.id), payload.role, device_id=str(device.id))
    return ClaimRoleResponse(
        spouse_id=spouse.id,
        device_id=device.id,
        role=payload.role,
        access_token=access_token,
        refresh_token=refresh_token,
        vmk_b64=base64.b64encode(vmk).decode(),
        server=f"https://{settings.domain}",
    )


@router.get("/me", response_model=SpouseOut)
async def get_me(spouse: Spouse = Depends(get_current_spouse)):
    return SpouseOut.from_spouse(spouse)


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


@router.post("/login/password", response_model=LoginPasswordResponse, dependencies=[Depends(rate_limit("login_password", max_attempts=10, window_seconds=300))])
async def login_password(payload: LoginPasswordRequest, db: AsyncSession = Depends(get_db)):
    """Password is now the only server-verified factor (DECISIONS.md #27
    removed the mandatory authenticator-code step) -- a correct password
    issues real tokens directly, or a face challenge first for spouses who
    opted into that extra step. Fast re-entry within an hour is handled
    entirely on-device via biometric unlock; the server is never involved
    in that at all, since the tokens are already sitting in secure storage
    from this call."""
    if payload.role not in ("husband", "wife"):
        raise HTTPException(status_code=400, detail="Invalid role")
    result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(payload.role)))
    spouse = result.scalar_one_or_none()
    if spouse is None or not verify_secret(payload.password, spouse.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if spouse.face_verification_enabled:
        face_challenge = _create_challenge_token(
            str(spouse.id), payload.role, payload.device_name, "face_challenge",
            device_uuid=payload.device_uuid,
        )
        db.add(AuditLogEntry(actor_id=spouse.id, action="auth.password_ok", target_type="spouse", target_id=spouse.id))
        await db.commit()
        return LoginPasswordResponse(requires_face=True, face_challenge_token=face_challenge)

    result_data = await _issue_full_login(db, spouse, payload.device_name, payload.device_uuid)
    return LoginPasswordResponse(requires_face=False, **result_data)


@router.post("/login/face", response_model=LoginFaceResponse, dependencies=[Depends(rate_limit("login_face", max_attempts=10, window_seconds=300))])
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

    device_id = claims.get("device_id")
    existing_device = await db.get(Device, uuid.UUID(device_id)) if device_id else None
    result_data = await _issue_full_login(
        db, spouse, claims.get("device_name", "device"), claims.get("device_uuid"), existing_device=existing_device,
    )
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

    # A deleted Device (revoked from the Devices screen) must not be able
    # to refresh its way back in. Older tokens minted before this device_id
    # fix (DECISIONS.md #16) won't carry a valid device_id and are treated
    # as revoked too -- they'll need to log in again, which is safe.
    device_id_claim = claims.get("device_id")
    device = None
    if device_id_claim:
        try:
            device_result = await db.execute(select(Device).where(Device.id == uuid.UUID(device_id_claim), Device.spouse_id == spouse_id))
            device = device_result.scalar_one_or_none()
        except ValueError:
            device = None
    if device is None:
        raise HTTPException(status_code=401, detail="This device has been removed. Please set up the app again.")
    device.last_seen_at = datetime.now(timezone.utc)
    await db.commit()

    access_token = create_access_token(str(spouse.id), spouse.role.value, device_id=str(device.id))
    return RefreshResponse(access_token=access_token)


@router.post("/duress/set")
async def set_duress_pin(payload: DuressSetRequest, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    if len(payload.pin) < 4:
        raise HTTPException(status_code=400, detail="PIN must be at least 4 digits")
    spouse.duress_pin_hash = hash_secret(payload.pin)
    await db.commit()
    return {"ok": True}


@router.post("/password-reset/initiate", dependencies=[Depends(rate_limit("password_reset", max_attempts=10, window_seconds=600))])
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


@router.post("/password-reset/approve", dependencies=[Depends(rate_limit("password_reset", max_attempts=10, window_seconds=600))])
async def password_reset_approve(payload: PasswordResetApproveRequest, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Replaces the old TOTP-code verification step (DECISIONS.md #27):
    since there's no authenticator code anymore, a password reset is
    approved by tapping a button on an ALREADY-AUTHENTICATED device --
    either spouse's, matching the app's existing full-mutual-trust model
    (either spouse can already revoke any device). Only one approval is
    required, not both."""
    result = await db.execute(select(PasswordResetSession).where(PasswordResetSession.reset_token == payload.reset_token))
    session = result.scalar_one_or_none()
    if session is None or session.used or session.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=404, detail="Reset session not found or expired")

    now = datetime.now(timezone.utc)
    if spouse.role == RoleEnum.husband:
        session.husband_verified_at = now
    else:
        session.wife_verified_at = now
    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.password_reset_approve", target_type="spouse", target_id=spouse.id))
    await db.commit()
    return {"approved": True}


@router.post("/password-reset/status")
async def password_reset_status(payload: PasswordResetStatusRequest, db: AsyncSession = Depends(get_db)):
    """Polled by the locked device waiting for an already-authenticated
    device to approve -- no push notifications involved (see
    DECISIONS.md's known limitation on those)."""
    result = await db.execute(select(PasswordResetSession).where(PasswordResetSession.reset_token == payload.reset_token))
    session = result.scalar_one_or_none()
    if session is None or session.used or session.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=404, detail="Reset session not found or expired")
    approved = session.husband_verified_at is not None or session.wife_verified_at is not None
    return {"approved": approved}


@router.post("/password-reset/complete")
async def password_reset_complete(payload: PasswordResetCompleteRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PasswordResetSession).where(PasswordResetSession.reset_token == payload.reset_token))
    session = result.scalar_one_or_none()
    if session is None or session.used or session.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=404, detail="Reset session not found or expired")
    if session.husband_verified_at is None and session.wife_verified_at is None:
        raise HTTPException(status_code=409, detail="An already-logged-in device must approve this reset first")

    spouse_result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(session.target_role)))
    spouse = spouse_result.scalar_one_or_none()
    if spouse is None:
        raise HTTPException(status_code=404, detail="Target spouse not found")

    spouse.password_hash = hash_secret(payload.new_password)
    session.used = True
    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.password_reset", target_type="spouse", target_id=spouse.id))
    await db.commit()
    return {"ok": True}
