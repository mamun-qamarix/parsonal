import uuid
from datetime import datetime

from sqlalchemy import String, ForeignKey, DateTime
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class NotificationLog(Base, UUIDPk, TimestampMixin):
    """A persisted record of every notify_spouse() event, per recipient --
    previously notifications were purely ephemeral (a WS ping + an
    optional push), so there was no in-app inbox/history at all. `body`
    is computed on read from `category`/`content_type` via the same
    generic-text table used for push notifications (see
    app/services/notifications.py) -- never stored pre-rendered, so a
    wording change there applies retroactively to old entries too."""

    __tablename__ = "notification_log"

    recipient_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("spouses.id", ondelete="CASCADE"), index=True
    )
    category: Mapped[str] = mapped_column(String(30), nullable=False)
    content_type: Mapped[str | None] = mapped_column(String(20), nullable=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
