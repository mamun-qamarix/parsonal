import uuid
from datetime import datetime

from pydantic import BaseModel


class NotificationOut(BaseModel):
    id: uuid.UUID
    category: str
    content_type: str | None
    body: str  # rendered generic text, see notification_body()
    created_at: datetime
    read_at: datetime | None


class UnreadCountOut(BaseModel):
    unread_count: int
