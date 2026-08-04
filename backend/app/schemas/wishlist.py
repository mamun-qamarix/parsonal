import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.common import ORMBase, EncPayloadIn


class WishlistItemCreate(EncPayloadIn):
    category_id: uuid.UUID | None = None


class WishlistItemUpdate(BaseModel):
    enc_payload: str | None = None
    is_fulfilled: bool | None = None
    category_id: uuid.UUID | None = None


class WishlistItemOut(ORMBase):
    id: uuid.UUID
    owner_id: uuid.UUID
    category_id: uuid.UUID | None
    enc_payload: str
    is_fulfilled: bool
    created_at: datetime
