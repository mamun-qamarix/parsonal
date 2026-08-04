import base64
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.deps import get_current_spouse, get_current_spouse_and_device
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

    spouse = Spouse(role=RoleEnum(payload.role), password_hash=hash_secret(payload.password))
    db.add(spouse)
    await db.flush()

    # TOTP is per-device (see DECISIONS.md): this first device gets its own
    # secret here; a later device paired onto this same role sets up its own.
    totp_secret = totp_service.generate_secret()
    device = Device(
        spouse_id=spouse.id,
        device_name=payload.device_name,
        device_uuid=payload.device_uuid,
        totp_secret=totp_secret,
        refresh_token_hash="",
    )
    db.add(device)
    await db.flush()

    refresh_token = create_refresh_token(str(spouse.id), device_id=str(device.id))
    device.refresh_token_hash = hash_secret(refresh_token)

    if payload.role == "husband":
        code.claimed_husband = True
    else:
        code.claimed_wife = True

    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.claim_role", target_type="spouse", target_id=spouse.id, detail=payload.role))

    fully_claimed = code.claimed_husband and code.claimed_wife
    if fully_claimed:
        await db.delete(code)

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
        totp_secret=totp_secret,
        totp_provisioning_uri=totp_service.provisioning_uri(totp_secret, f"{payload.role}@couplevault"),
    )


@router.get("/me", response_model=SpouseOut)
async def get_me(ctx: tuple[Spouse, Device | None] = Depends(get_current_spouse_and_device)):
    spouse, device = ctx
    return SpouseOut.from_spouse(spouse, device)


@router.get("/totp/setup-info")
async def totp_setup_info(ctx: tuple[Spouse, Device | None] = Depends(get_current_spouse_and_device)):
    """Lets the app recover the QR/secret if the user was interrupted
    mid-onboarding (e.g. backgrounded the app to install/open their
    authenticator app) before confirming -- see DECISIONS.md #14. TOTP is
    per-device (DECISIONS.md #21), so this reflects THIS device's secret."""
    spouse, device = ctx
    if device is None:
        raise HTTPException(status_code=409, detail="No device associated with this session")
    if device.totp_confirmed:
        raise HTTPException(status_code=409, detail="Authenticator app already confirmed for this device")
    if device.totp_secret is None:
        raise HTTPException(status_code=409, detail="No TOTP secret on file for this device")
    return {
        "totp_secret": device.totp_secret,
        "totp_provisioning_uri": totp_service.provisioning_uri(device.totp_secret, f"{spouse.role.value}@couplevault"),
    }


@router.post("/totp/setup-confirm")
async def totp_setup_confirm(
    payload: TotpSetupConfirmRequest,
    ctx: tuple[Spouse, Device | None] = Depends(get_current_spouse_and_device),
    db: AsyncSession = Depends(get_db),
):
    """Proves this device actually saved the TOTP secret into an
    authenticator app before we start requiring it at every login on it."""
    spouse, device = ctx
    if device is None:
        raise HTTPException(status_code=409, detail="No device associated with this session")
    if device.totp_secret is None:
        raise HTTPException(status_code=409, detail="No TOTP secret on file for this device")
    if not totp_service.verify_code(device.totp_secret, payload.code):
        raise HTTPException(status_code=401, detail="Invalid authenticator code")
    device.totp_confirmed = True
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

    # Password is shared across a spouse's devices; the authenticator code
    # is per-device (DECISIONS.md #21). A device we've never seen confirm
    # one before (new install, or newly paired onto this role) needs to set
    # up its OWN authenticator entry first, instead of being asked for a
    # code that only exists on a different phone.
    device = await _find_device(db, spouse.id, payload.device_uuid)
    if device is not None and device.totp_confirmed:
        challenge = _create_challenge_token(
            str(spouse.id), payload.role, payload.device_name, "totp_challenge",
            device_uuid=payload.device_uuid, device_id=str(device.id),
        )
        return LoginPasswordResponse(mode="verify", challenge_token=challenge)

    if device is None:
        device = Device(
            spouse_id=spouse.id, device_name=payload.device_name, device_uuid=payload.device_uuid,
            totp_secret=totp_service.generate_secret(), refresh_token_hash="",
        )
        db.add(device)
        await db.flush()
    elif device.totp_secret is None:
        device.totp_secret = totp_service.generate_secret()
    # else: device exists, unconfirmed, already has a pending secret --
    # reuse it so a resumed setup (e.g. backgrounded to install an
    # authenticator app) shows the SAME QR, same resumability precedent as
    # DECISIONS.md #14.
    device.device_name = payload.device_name
    await db.commit()

    setup_challenge = _create_challenge_token(
        str(spouse.id), payload.role, payload.device_name, "totp_setup_challenge", minutes=15,
        device_uuid=payload.device_uuid, device_id=str(device.id),
    )
    return LoginPasswordResponse(
        mode="setup",
        setup_challenge_token=setup_challenge,
        totp_secret=device.totp_secret,
        totp_provisioning_uri=totp_service.provisioning_uri(device.totp_secret, f"{payload.role}@couplevault"),
    )


async def _after_totp_verified(db: AsyncSession, spouse: Spouse, device: Device, device_name: str, device_uuid: str | None) -> LoginTotpResponse:
    if spouse.face_verification_enabled:
        face_challenge = _create_challenge_token(
            str(spouse.id), spouse.role.value, device_name, "face_challenge",
            device_uuid=device_uuid, device_id=str(device.id),
        )
        db.add(AuditLogEntry(actor_id=spouse.id, action="auth.totp_verify_ok", target_type="spouse", target_id=spouse.id))
        await db.commit()
        return LoginTotpResponse(requires_face=True, face_challenge_token=face_challenge)

    result_data = await _issue_full_login(db, spouse, device_name, device_uuid, existing_device=device)
    return LoginTotpResponse(requires_face=False, **result_data)


@router.post("/login/totp-setup-confirm", response_model=LoginTotpResponse)
async def login_totp_setup_confirm(payload: LoginTotpRequest, db: AsyncSession = Depends(get_db)):
    """Confirms a NEW device's own authenticator entry mid-login (device
    was paired onto an already-claimed role, or is a fresh install) --
    counterpart to /auth/totp/setup-confirm, which is only reachable with a
    real access token and is used for the very first device at claim time.
    See DECISIONS.md #21."""
    try:
        claims = decode_token_safe(payload.challenge_token)
    except TokenError:
        raise HTTPException(status_code=401, detail="Invalid or expired challenge token")
    if claims.get("type") != "totp_setup_challenge":
        raise HTTPException(status_code=401, detail="Invalid challenge token")

    spouse_id = uuid.UUID(claims["sub"])
    result = await db.execute(select(Spouse).where(Spouse.id == spouse_id))
    spouse = result.scalar_one_or_none()
    if spouse is None:
        raise HTTPException(status_code=404, detail="Spouse not found")

    device_id = claims.get("device_id")
    device = await db.get(Device, uuid.UUID(device_id)) if device_id else None
    if device is None or device.totp_secret is None:
        raise HTTPException(status_code=404, detail="Device not found")

    if not totp_service.verify_code(device.totp_secret, payload.code):
        raise HTTPException(status_code=401, detail="Invalid authenticator code")

    device.totp_confirmed = True
    db.add(AuditLogEntry(actor_id=spouse.id, action="auth.totp_setup_confirm", target_type="spouse", target_id=spouse.id))
    await db.commit()

    return await _after_totp_verified(db, spouse, device, claims.get("device_name", "device"), claims.get("device_uuid"))


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
    if spouse is None:
        raise HTTPException(status_code=404, detail="Spouse not found")

    device_id = claims.get("device_id")
    device = await db.get(Device, uuid.UUID(device_id)) if device_id else None
    if device is None or device.totp_secret is None or not device.totp_confirmed:
        raise HTTPException(status_code=404, detail="Device not found")

    if not totp_service.verify_code(device.totp_secret, payload.code):
        db.add(AuditLogEntry(actor_id=spouse.id, action="auth.totp_verify_failed", target_type="spouse", target_id=spouse.id))
        await db.commit()
        raise HTTPException(status_code=401, detail="Invalid authenticator code")

    device_name = claims.get("device_name", "device")
    device_uuid = claims.get("device_uuid")
    return await _after_totp_verified(db, spouse, device, device_name, device_uuid)


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
    if spouse is None:
        raise HTTPException(status_code=404, detail="Spouse not found")

    # TOTP is per-device (DECISIONS.md #21) and password reset doesn't know
    # which of a spouse's devices they're holding, so a code from ANY of
    # that spouse's confirmed devices counts as that spouse verifying.
    devices_result = await db.execute(
        select(Device).where(Device.spouse_id == spouse.id, Device.totp_confirmed == True)  # noqa: E712
    )
    devices = devices_result.scalars().all()
    if not devices or not any(d.totp_secret and totp_service.verify_code(d.totp_secret, payload.code) for d in devices):
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
