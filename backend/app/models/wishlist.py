import uuid

from sqlalchemy import Boolean, ForeignKey, LargeBinary
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class WishlistItem(Base, UUIDPk, TimestampMixin):
    __tablename__ = "wishlist_items"

    owner_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    category_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("categories.id", ondelete="SET NULL"), nullable=True)
    enc_payload: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    is_fulfilled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
