from datetime import datetime

from sqlalchemy import String, Boolean, DateTime, LargeBinary
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class SetupCode(Base, UUIDPk, TimestampMixin):
    __tablename__ = "setup_codes"

    token: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    vmk_encrypted: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    claimed_husband: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    claimed_wife: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
