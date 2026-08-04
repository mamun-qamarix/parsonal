import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.common import ORMBase, EncPayloadIn


class ReactionCreate(BaseModel):
    target_type: str
    target_id: uuid.UUID
    emoji: str


class CommentCreate(EncPayloadIn):
    target_type: str
    target_id: uuid.UUID


class CommentOut(ORMBase):
    id: uuid.UUID
    target_type: str
    target_id: uuid.UUID
    author_id: uuid.UUID
    author_role: str
    enc_payload: str
    created_at: datetime
    heart_count: int = 0
    hearted_by_me: bool = False


class FavoriteToggle(BaseModel):
    target_type: str
    target_id: uuid.UUID
