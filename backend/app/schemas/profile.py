import uuid
from datetime import datetime

from pydantic import BaseModel


class ProfileUpdate(BaseModel):
    enc_display_name: str | None = None
    enc_bio: str | None = None
    enc_anniversary_dates: str | None = None
    profile_photo_asset_id: uuid.UUID | None = None


class ProfileOut(BaseModel):
    spouse_id: uuid.UUID
    role: str
    enc_display_name: str | None
    enc_bio: str | None
    enc_anniversary_dates: str | None
    profile_photo_asset_id: uuid.UUID | None
    updated_at: datetime | None


class CountdownSet(BaseModel):
    target_datetime: datetime
    enc_note: str | None = None


class CountdownOut(BaseModel):
    target_datetime: datetime
    set_by: uuid.UUID
    enc_note: str | None
    updated_at: datetime


class AppSettingOut(BaseModel):
    key: str
    value: str


class AppSettingUpdate(BaseModel):
    value: str
