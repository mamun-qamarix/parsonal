import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.common import ORMBase, EncPayloadIn


class CategoryCreate(EncPayloadIn):
    scope: str  # "vault" | "wishlist"


class CategoryOut(ORMBase):
    id: uuid.UUID
    scope: str
    enc_name: str
    created_by: uuid.UUID
    created_at: datetime


class MediaAssetOut(ORMBase):
    id: uuid.UUID
    kind: str
    size_bytes: int
    has_thumbnail: bool = False


class VaultEntryCreate(EncPayloadIn):
    content_type: str  # text | photo | video
    category_id: uuid.UUID | None = None
    media_asset_ids: list[uuid.UUID] = []


class VaultEntryOut(ORMBase):
    id: uuid.UUID
    content_type: str
    category_id: uuid.UUID | None
    author_id: uuid.UUID
    author_role: str
    enc_payload: str
    created_at: datetime
    updated_at: datetime
    is_favorite_mine: bool = False
    view_count: int = 0
    media_assets: list[MediaAssetOut] = []


class EditRequestCreate(EncPayloadIn):
    pass


class VaultEntryEdit(EncPayloadIn):
    category_id: uuid.UUID | None = None


class ConsentRequestOut(ORMBase):
    id: uuid.UUID
    entry_id: uuid.UUID
    action: str
    requested_by: uuid.UUID
    status: str
    created_at: datetime


class ConsentDecision(BaseModel):
    approve: bool
