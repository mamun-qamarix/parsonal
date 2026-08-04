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

    # Mandatory second factor: TOTP (Google Authenticator / Authy / etc).
    # totp_secret is generated at claim time; totp_confirmed only flips to
    # True once the spouse has proven they actually saved it (entered one
    # valid code back) -- see DECISIONS.md.
    totp_secret: Mapped[str | None] = mapped_column(String(64), nullable=True)
    totp_confirmed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # Face verification is optional, opt-in from Settings/Profile -- see
    # DECISIONS.md. face_enrolled: has ever completed CompreFace enrollment.
    # face_verification_enabled: currently required as an extra login step.
    compreface_subject: Mapped[str | None] = mapped_column(String(64), nullable=True)
    face_enrolled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    face_verification_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    devices: Mapped[list["Device"]] = relationship(back_populates="spouse", cascade="all, delete-orphan")


class Device(Base, UUIDPk, TimestampMixin):
    __tablename__ = "devices"

    spouse_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    device_name: Mapped[str] = mapped_column(String(120), nullable=False)
    # Stable per-installation identifier the app generates once and keeps
    # (outside the data wiped by logout). Lets repeated logins from the
    # same physical phone reuse this row instead of piling up duplicates.
    # Nullable: older app versions never sent one, and rows created before
    # this column existed have none. See DECISIONS.md.
    device_uuid: Mapped[str | None] = mapped_column(String(64), nullable=True)
    push_token: Mapped[str | None] = mapped_column(String(255), nullable=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)

    spouse: Mapped["Spouse"] = relationship(back_populates="devices")
