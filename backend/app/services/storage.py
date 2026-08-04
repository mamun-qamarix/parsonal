import io
import uuid

from minio import Minio
from minio.error import S3Error

from app.config import get_settings

settings = get_settings()

_client = Minio(
    settings.minio_endpoint,
    access_key=settings.minio_access_key,
    secret_key=settings.minio_secret_key,
    secure=settings.minio_secure,
)


def ensure_bucket() -> None:
    if not _client.bucket_exists(settings.minio_bucket):
        _client.make_bucket(settings.minio_bucket)


def put_object(data: bytes, content_type: str = "application/octet-stream") -> str:
    ensure_bucket()
    object_key = f"{uuid.uuid4()}"
    _client.put_object(
        settings.minio_bucket,
        object_key,
        io.BytesIO(data),
        length=len(data),
        content_type=content_type,
    )
    return object_key


def get_object(object_key: str) -> bytes:
    response = None
    try:
        response = _client.get_object(settings.minio_bucket, object_key)
        return response.read()
    except S3Error as exc:
        raise FileNotFoundError(object_key) from exc
    finally:
        if response is not None:
            response.close()
            response.release_conn()


def delete_object(object_key: str) -> None:
    _client.remove_object(settings.minio_bucket, object_key)
