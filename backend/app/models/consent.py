import enum
import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, LargeBinary, DateTime, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class ConsentActionEnum(str, enum.Enum):
    edit = "edit"
    delete = "delete"


class ConsentStatusEnum(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"


class ConsentRequest(Base, UUIDPk, TimestampMixin):
    __tablename__ = "consent_requests"

    entry_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("vault_entries.id", ondelete="CASCADE"))
    action: Mapped[ConsentActionEnum] = mapped_column(SAEnum(ConsentActionEnum, name="consent_action_enum"), nullable=False)
    requested_by: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    new_enc_payload: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    status: Mapped[ConsentStatusEnum] = mapped_column(SAEnum(ConsentStatusEnum, name="consent_status_enum"), default=ConsentStatusEnum.pending, nullable=False)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    resolved_by: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="SET NULL"), nullable=True)
