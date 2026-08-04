import uuid

from sqlalchemy import String, ForeignKey, LargeBinary, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class Reaction(Base, UUIDPk, TimestampMixin):
    __tablename__ = "reactions"
    __table_args__ = (UniqueConstraint("target_type", "target_id", "spouse_id", "emoji", name="uq_reaction"),)

    target_type: Mapped[str] = mapped_column(String(30), nullable=False)  # vault_entry | comment | chat_message | phrase
    target_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    spouse_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    emoji: Mapped[str] = mapped_column(String(16), nullable=False)


class Comment(Base, UUIDPk, TimestampMixin):
    __tablename__ = "comments"

    target_type: Mapped[str] = mapped_column(String(30), nullable=False)
    target_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    author_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    enc_payload: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)


class Favorite(Base, UUIDPk, TimestampMixin):
    __tablename__ = "favorites"
    __table_args__ = (UniqueConstraint("spouse_id", "target_type", "target_id", name="uq_favorite"),)

    spouse_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    target_type: Mapped[str] = mapped_column(String(30), nullable=False)  # vault_entry | phrase
    target_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)


class MatchCelebrationSeen(Base, UUIDPk, TimestampMixin):
    __tablename__ = "match_celebration_seen"
    __table_args__ = (UniqueConstraint("spouse_id", "target_type", "target_id", name="uq_match_seen"),)

    spouse_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"))
    target_type: Mapped[str] = mapped_column(String(30), nullable=False)
    target_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
