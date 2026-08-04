import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, LargeBinary, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, utcnow


class Profile(Base, UUIDPk):
    __tablename__ = "profiles"

    spouse_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"), unique=True)
    enc_display_name: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    enc_bio: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    enc_anniversary_dates: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    profile_photo_asset_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("media_assets.id", ondelete="SET NULL"), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)
