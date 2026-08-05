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


class ReactionPersonGroup(BaseModel):
    """One row per person who's reacted -- all their emoji, in the order
    they added them, no per-emoji counts. Replaces the old per-emoji-
    grouped ReactionBreakdown shape now that reacting with several
    different emoji (not just toggling a fixed preset) is the point. See
    DECISIONS.md."""

    role: str
    emojis: list[str]
    is_me: bool
