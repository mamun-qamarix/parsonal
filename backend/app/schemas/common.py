import base64
import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, field_validator


class ORMBase(BaseModel):
    model_config = ConfigDict(from_attributes=True)


def b64_to_bytes(value: str) -> bytes:
    try:
        return base64.b64decode(value)
    except Exception as exc:
        raise ValueError("enc_payload must be valid base64") from exc


def bytes_to_b64(value: bytes | None) -> str | None:
    if value is None:
        return None
    return base64.b64encode(value).decode("ascii")


class EncPayloadIn(BaseModel):
    enc_payload: str  # base64-encoded ciphertext blob, opaque to the server

    @field_validator("enc_payload")
    @classmethod
    def validate_b64(cls, v: str) -> str:
        b64_to_bytes(v)
        return v


class ReactionBreakdown(BaseModel):
    emoji: str
    husband_count: int
    wife_count: int
    reacted_by_me: bool
