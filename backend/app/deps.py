import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import Spouse, Device
from app.services.security import decode_token_safe, TokenError

bearer_scheme = HTTPBearer(auto_error=True)


async def _resolve_spouse_and_device(
    credentials: HTTPAuthorizationCredentials, db: AsyncSession
) -> tuple[Spouse, Device | None]:
    try:
        payload = decode_token_safe(credentials.credentials)
    except TokenError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")

    if payload.get("type") != "access":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token type")

    spouse_id = payload.get("sub")
    try:
        spouse_uuid = uuid.UUID(spouse_id)
    except (TypeError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid subject")

    result = await db.execute(select(Spouse).where(Spouse.id == spouse_uuid, Spouse.is_active == True))  # noqa: E712
    spouse = result.scalar_one_or_none()
    if spouse is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Spouse not found")

    device = None
    device_id = payload.get("device_id")
    if device_id:
        try:
            device = await db.get(Device, uuid.UUID(device_id))
        except (TypeError, ValueError):
            device = None
    return spouse, device


async def get_current_spouse(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Spouse:
    spouse, _ = await _resolve_spouse_and_device(credentials, db)
    return spouse


async def get_current_spouse_and_device(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> tuple[Spouse, Device | None]:
    """Like get_current_spouse, but also resolves the calling Device (from
    the access token's device_id claim) -- needed by endpoints that operate
    on per-device state like TOTP. See DECISIONS.md."""
    return await _resolve_spouse_and_device(credentials, db)


def other_role(role: str) -> str:
    return "wife" if role == "husband" else "husband"
