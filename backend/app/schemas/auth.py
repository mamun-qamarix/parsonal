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
    totp_secret: str
    totp_provisioning_uri: str


class TotpSetupConfirmRequest(BaseModel):
    code: str


class LoginPasswordRequest(BaseModel):
    role: str
    password: str
    device_name: str
    device_uuid: str | None = None


class LoginPasswordResponse(BaseModel):
    challenge_token: str  # short-lived token proving password step passed; TOTP step required next


class LoginTotpRequest(BaseModel):
    challenge_token: str
    code: str


class LoginTotpResponse(BaseModel):
    requires_face: bool
    # Present when requires_face is True: pass this to /auth/login/face.
    face_challenge_token: str | None = None
    # Present when requires_face is False: login is already complete.
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


class PasswordResetVerifyRequest(BaseModel):
    reset_token: str
    role: str
    code: str  # TOTP code, not face -- see DECISIONS.md


class PasswordResetCompleteRequest(BaseModel):
    reset_token: str
    new_password: str


class SpouseOut(BaseModel):
    id: uuid.UUID
    role: str
    face_enrolled: bool
    face_verification_enabled: bool
    totp_confirmed: bool

    @classmethod
    def from_spouse(cls, spouse) -> "SpouseOut":
        return cls(
            id=spouse.id,
            role=spouse.role.value,
            face_enrolled=spouse.face_enrolled,
            face_verification_enabled=spouse.face_verification_enabled,
            totp_confirmed=spouse.totp_confirmed,
        )
