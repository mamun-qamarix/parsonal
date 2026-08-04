from datetime import datetime

from sqlalchemy import String, DateTime, Boolean

from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class PasswordResetSession(Base, UUIDPk, TimestampMixin):
    __tablename__ = "password_reset_sessions"

    target_role: Mapped[str] = mapped_column(String(10), nullable=False)
    reset_token: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    husband_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    wife_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
