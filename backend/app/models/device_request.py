import uuid
from datetime import datetime

from sqlalchemy import String, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class DeviceRequest(Base, UUIDPk, TimestampMixin):
    """A phone that entered the correct master password but hasn't been
    approved yet. It shows up in the admin panel; once the admin approves
    it (and picks husband/wife), the waiting phone's next poll turns it
    into a real Device + tokens. See DECISIONS.md #54.

    Kept separate from Device on purpose: a Device always belongs to a
    Spouse, but a pending phone doesn't have a role yet."""
    __tablename__ = "device_requests"

    device_uuid: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    device_name: Mapped[str] = mapped_column(String(120), nullable=False)
    # Short human code shown on the waiting phone AND in the admin panel,
    # so the admin can be sure they're approving the phone in their hand.
    code: Mapped[str] = mapped_column(String(12), nullable=False)
    # Only the phone that actually typed the right password knows this --
    # it's what lets that phone (and nobody else) collect tokens once
    # approved.
    poll_secret_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")  # pending | approved | rejected
    role: Mapped[str | None] = mapped_column(String(16), nullable=True)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
