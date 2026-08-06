import enum
import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, LargeBinary, DateTime, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class ChatContentTypeEnum(str, enum.Enum):
    text = "text"
    photo = "photo"
    video = "video"
    voice = "voice"
    file = "file"


class ChatMessage(Base, UUIDPk, TimestampMixin):
    __tablename__ = "chat_messages"

    sender_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    content_type: Mapped[ChatContentTypeEnum] = mapped_column(SAEnum(ChatContentTypeEnum, name="chat_content_type_enum"), nullable=False)
    enc_payload: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)

    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    reply_to_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("chat_messages.id", ondelete="SET NULL"), nullable=True
    )

    media_assets: Mapped[list["MediaAsset"]] = relationship(back_populates=None, viewonly=True,
                                                              primaryjoin="ChatMessage.id==MediaAsset.chat_message_id")
