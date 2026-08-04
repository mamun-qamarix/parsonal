import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.common import ORMBase


class SetupCodeCreateResponse(BaseModel):
    token: str
    server: str
    vmk_b64: str
    qr_payload: str
    expires_at: datetime


class ClaimRoleRequest(BaseModel):
    token: str
    role: str  # "husband" | "wife"
    password: str
    device_name: str


class ClaimRoleResponse(BaseModel):
    spouse_id: uuid.UUID
    role: str
    face_enrolled: bool
    access_token: str
    refresh_token: str
    vmk_b64: str
    server: str


class LoginPasswordRequest(BaseModel):
    role: str
    password: str
    device_name: str


class LoginPasswordResponse(BaseModel):
    challenge_token: str  # short-lived token proving password step passed; face step required next


class LoginFaceRequest(BaseModel):
    challenge_token: str
    face_image_b64: str


class LoginFaceResponse(BaseModel):
    access_token: str
    refresh_token: str
    spouse_id: uuid.UUID
    role: str


class RefreshRequest(BaseModel):
    refresh_token: str


class RefreshResponse(BaseModel):
    access_token: str


class FaceEnrollRequest(BaseModel):
    face_image_b64: str


class DuressSetRequest(BaseModel):
    pin: str


class PasswordResetInitiateRequest(BaseModel):
    role: str


class PasswordResetVerifyRequest(BaseModel):
    reset_token: str
    role: str
    face_image_b64: str


class PasswordResetCompleteRequest(BaseModel):
    reset_token: str
    new_password: str


class SpouseOut(ORMBase):
    id: uuid.UUID
    role: str
    face_enrolled: bool
