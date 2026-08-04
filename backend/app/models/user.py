import enum
import uuid
from datetime import datetime

from sqlalchemy import String, Boolean, ForeignKey, DateTime, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin, utcnow


class RoleEnum(str, enum.Enum):
    husband = "husband"
    wife = "wife"


class Spouse(Base, UUIDPk, TimestampMixin):
    __tablename__ = "spouses"

    role: Mapped[RoleEnum] = mapped_column(SAEnum(RoleEnum, name="role_enum"), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    duress_pin_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)

    compreface_subject: Mapped[str | None] = mapped_column(String(64), nullable=True)
    face_enrolled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    devices: Mapped[list["Device"]] = relationship(back_populates="spouse", cascade="all, delete-orphan")


class Device(Base, UUIDPk, TimestampMixin):
    __tablename__ = "devices"

    spouse_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    device_name: Mapped[str] = mapped_column(String(120), nullable=False)
    push_token: Mapped[str | None] = mapped_column(String(255), nullable=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)

    spouse: Mapped["Spouse"] = relationship(back_populates="devices")
