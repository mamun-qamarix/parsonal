import uuid
from datetime import datetime

from app.schemas.common import ORMBase


class AuditLogOut(ORMBase):
    id: uuid.UUID
    actor_id: uuid.UUID | None
    action: str
    target_type: str | None
    target_id: uuid.UUID | None
    detail: str | None
    created_at: datetime


class ContentViewOut(ORMBase):
    id: uuid.UUID
    entry_id: uuid.UUID
    viewer_id: uuid.UUID
    created_at: datetime
