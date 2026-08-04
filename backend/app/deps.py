import uuid

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import Spouse
from app.services.security import decode_token_safe, TokenError

bearer_scheme = HTTPBearer(auto_error=True)


async def get_current_spouse(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Spouse:
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
    return spouse


def other_role(role: str) -> str:
    return "wife" if role == "husband" else "husband"
