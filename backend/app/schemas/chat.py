import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.common import ORMBase


class ChatMessageCreate(BaseModel):
    content_type: str  # text | photo | video | voice | file
    enc_payload: str | None = None
    media_asset_id: uuid.UUID | None = None


class ChatMessageOut(ORMBase):
    id: uuid.UUID
    sender_id: uuid.UUID
    sender_role: str
    content_type: str
    enc_payload: str | None
    created_at: datetime
    delivered_at: datetime | None
    read_at: datetime | None
    media_asset_id: uuid.UUID | None = None
    media_has_thumbnail: bool = False


class ChatMediaOut(BaseModel):
    """One entry per photo/video ever exchanged in chat -- powers the
    gallery screen (see DECISIONS.md), so a couple can browse everything
    they've shared without scrolling back through the whole conversation."""

    message_id: uuid.UUID
    media_asset_id: uuid.UUID
    content_type: str  # photo | video
    has_thumbnail: bool
    created_at: datetime
