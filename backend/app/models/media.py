import enum
import uuid

from sqlalchemy import Boolean, String, Integer, ForeignKey, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class MediaKindEnum(str, enum.Enum):
    image = "image"
    video = "video"
    voice = "voice"
    file = "file"


class MediaAsset(Base, UUIDPk, TimestampMixin):
    __tablename__ = "media_assets"

    entry_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("vault_entries.id", ondelete="CASCADE"), nullable=True)
    chat_message_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("chat_messages.id", ondelete="CASCADE"), nullable=True)
    profile_owner_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"), nullable=True)

    kind: Mapped[MediaKindEnum] = mapped_column(SAEnum(MediaKindEnum, name="media_kind_enum"), nullable=False)
    object_key: Mapped[str] = mapped_column(String(255), nullable=False)
    thumbnail_object_key: Mapped[str | None] = mapped_column(String(255), nullable=True)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # True = encrypted in independently-authenticated chunks (streamable
    # video, see DECISIONS.md). False = the original single-blob format.
    chunked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    # When an old single-blob video is converted to the chunked format the
    # original ciphertext object is KEPT (never deleted) and remembered here.
    legacy_object_key: Mapped[str | None] = mapped_column(String(255), nullable=True)

    entry: Mapped["VaultEntry"] = relationship(back_populates="media_assets")
