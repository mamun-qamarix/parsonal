from datetime import datetime, timedelta, timezone

from fastapi import Cookie, Depends, HTTPException, status
from jose import jwt, JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.models.misc import AppSetting

settings = get_settings()
ADMIN_PASSWORD_KEY = "admin_password_hash"


def create_admin_session_token() -> str:
    expire = datetime.now(timezone.utc) + timedelta(hours=12)
    return jwt.encode({"type": "admin", "exp": expire}, settings.jwt_secret, algorithm=settings.jwt_algorithm)


async def require_admin(admin_session: str | None = Cookie(default=None)) -> None:
    if not admin_session:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Admin login required")
    try:
        claims = jwt.decode(admin_session, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid admin session")
    if claims.get("type") != "admin":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid admin session")


async def get_admin_password_hash(db: AsyncSession) -> str | None:
    result = await db.execute(select(AppSetting).where(AppSetting.key == ADMIN_PASSWORD_KEY))
    row = result.scalar_one_or_none()
    return row.value if row else None


async def set_admin_password_hash(db: AsyncSession, hashed: str) -> None:
    result = await db.execute(select(AppSetting).where(AppSetting.key == ADMIN_PASSWORD_KEY))
    row = result.scalar_one_or_none()
    if row:
        row.value = hashed
    else:
        db.add(AppSetting(key=ADMIN_PASSWORD_KEY, value=hashed))
    await db.commit()
