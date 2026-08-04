import uuid
from datetime import datetime

from pydantic import BaseModel


class DeviceOut(BaseModel):
    id: uuid.UUID
    device_name: str
    role: str
    is_this_device: bool
    created_at: datetime
    last_seen_at: datetime
