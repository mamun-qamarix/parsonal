import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.common import ORMBase, EncPayloadIn


class PhraseCreate(EncPayloadIn):
    direction: str  # husband_to_wife | wife_to_husband


class PhraseRate(BaseModel):
    rating: int  # 1-5


class PhraseOut(ORMBase):
    id: uuid.UUID
    direction: str
    author_id: uuid.UUID
    enc_payload: str
    rating_husband: int | None
    rating_wife: int | None
    created_at: datetime
