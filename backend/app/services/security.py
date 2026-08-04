import base64
import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from jose import jwt, JWTError
from passlib.context import CryptContext
from cryptography.fernet import Fernet

from app.config import get_settings

settings = get_settings()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_secret(value: str) -> str:
    return pwd_context.hash(value)


def verify_secret(value: str, hashed: str) -> bool:
    return pwd_context.verify(value, hashed)


def _fernet() -> Fernet:
    key = hashlib.sha256(settings.admin_panel_secret.encode()).digest()
    return Fernet(base64.urlsafe_b64encode(key))


def encrypt_at_rest(raw: bytes) -> bytes:
    return _fernet().encrypt(raw)


def decrypt_at_rest(token: bytes) -> bytes:
    return _fernet().decrypt(token)


def generate_setup_token() -> str:
    return secrets.token_urlsafe(24)


def generate_vmk() -> bytes:
    return secrets.token_bytes(32)


def create_access_token(subject: str, role: str, device_id: str | None = None) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes)
    payload = {"sub": subject, "role": role, "exp": expire, "type": "access"}
    if device_id:
        payload["device_id"] = device_id
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_refresh_token(subject: str, device_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_expire_days)
    payload = {"sub": subject, "device_id": device_id, "exp": expire, "type": "refresh"}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])


class TokenError(Exception):
    pass


def decode_token_safe(token: str) -> dict:
    try:
        return decode_token(token)
    except JWTError as exc:
        raise TokenError(str(exc)) from exc
