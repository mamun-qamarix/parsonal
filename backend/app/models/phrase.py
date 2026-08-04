import enum
import uuid

from sqlalchemy import Integer, ForeignKey, LargeBinary, Enum as SAEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class DirectionEnum(str, enum.Enum):
    husband_to_wife = "husband_to_wife"
    wife_to_husband = "wife_to_husband"


class Phrase(Base, UUIDPk, TimestampMixin):
    __tablename__ = "phrases"

    direction: Mapped[DirectionEnum] = mapped_column(SAEnum(DirectionEnum, name="direction_enum"), nullable=False)
    author_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    enc_payload: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)

    rating_husband: Mapped[int | None] = mapped_column(Integer, nullable=True)
    rating_wife: Mapped[int | None] = mapped_column(Integer, nullable=True)
