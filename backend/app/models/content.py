import enum
import uuid
from datetime import datetime

from sqlalchemy import String, Boolean, ForeignKey, LargeBinary, DateTime, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin, utcnow


class ContentTypeEnum(str, enum.Enum):
    text = "text"
    photo = "photo"
    video = "video"


class Category(Base, UUIDPk, TimestampMixin):
    __tablename__ = "categories"

    scope: Mapped[str] = mapped_column(String(20), nullable=False)  # "vault" | "wishlist"
    enc_name: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    created_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))


class VaultEntry(Base, UUIDPk, TimestampMixin):
    __tablename__ = "vault_entries"

    content_type: Mapped[ContentTypeEnum] = mapped_column(SAEnum(ContentTypeEnum, name="content_type_enum"), nullable=False)
    category_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("categories.id", ondelete="SET NULL"), nullable=True)
    author_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))

    enc_payload: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)

    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    media_assets: Mapped[list["MediaAsset"]] = relationship(back_populates="entry", cascade="all, delete-orphan")
