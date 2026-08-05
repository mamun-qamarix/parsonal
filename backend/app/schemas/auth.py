import uuid
from datetime import datetime

from pydantic import BaseModel


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
    device_uuid: str | None = None


class ClaimRoleResponse(BaseModel):
    spouse_id: uuid.UUID
    device_id: uuid.UUID
    role: str
    access_token: str
    refresh_token: str
    vmk_b64: str
    server: str


class LoginPasswordRequest(BaseModel):
    role: str
    password: str
    device_name: str
    device_uuid: str | None = None


class LoginPasswordResponse(BaseModel):
    """Password is the only server-verified factor now (device biometric
    unlock, DECISIONS.md #27, is a local-only gate on the already-issued
    tokens -- it never talks to the server). requires_face is True only
    for spouses who opted into the extra face-verification step."""
    requires_face: bool
    face_challenge_token: str | None = None
    access_token: str | None = None
    refresh_token: str | None = None
    spouse_id: uuid.UUID | None = None
    device_id: uuid.UUID | None = None
    role: str | None = None


class LoginFaceRequest(BaseModel):
    challenge_token: str
    face_image_b64: str


class LoginFaceResponse(BaseModel):
    access_token: str
    refresh_token: str
    spouse_id: uuid.UUID
    device_id: uuid.UUID
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


class PasswordResetApproveRequest(BaseModel):
    reset_token: str


class PasswordResetStatusRequest(BaseModel):
    reset_token: str


class PasswordResetCompleteRequest(BaseModel):
    reset_token: str
    new_password: str


class SpouseOut(BaseModel):
    id: uuid.UUID
    role: str
    face_enrolled: bool
    face_verification_enabled: bool

    @classmethod
    def from_spouse(cls, spouse, device=None) -> "SpouseOut":
        return cls(
            id=spouse.id,
            role=spouse.role.value,
            face_enrolled=spouse.face_enrolled,
            face_verification_enabled=spouse.face_verification_enabled,
        )
