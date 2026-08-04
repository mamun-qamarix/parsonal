import uuid
from typing import BinaryIO

from minio import Minio
from minio.error import S3Error
from starlette.concurrency import run_in_threadpool

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


def _put_object_sync(fileobj: BinaryIO, length: int, content_type: str) -> str:
    ensure_bucket()
    object_key = f"{uuid.uuid4()}"
    if length >= 0:
        _client.put_object(settings.minio_bucket, object_key, fileobj, length=length, content_type=content_type)
    else:
        # Unknown length -- MinIO switches to a chunked multipart upload
        # instead of needing the whole size up front.
        _client.put_object(settings.minio_bucket, object_key, fileobj, length=-1, part_size=10 * 1024 * 1024, content_type=content_type)
    return object_key


async def put_object(fileobj: BinaryIO, length: int = -1, content_type: str = "application/octet-stream") -> str:
    """Streams straight from `fileobj` (e.g. UploadFile.file) instead of
    requiring the whole thing already materialized as `bytes` -- matters
    once uploads can be up to 1GB (see DECISIONS.md). The MinIO client is
    synchronous, so this always runs off the event loop; without that, one
    big upload/download would stall every other request (chat, other
    users' API calls) for as long as it takes."""
    return await run_in_threadpool(_put_object_sync, fileobj, length, content_type)


def _get_object_sync(object_key: str) -> bytes:
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


async def get_object(object_key: str) -> bytes:
    return await run_in_threadpool(_get_object_sync, object_key)


def _delete_object_sync(object_key: str) -> None:
    _client.remove_object(settings.minio_bucket, object_key)


async def delete_object(object_key: str) -> None:
    await run_in_threadpool(_delete_object_sync, object_key)
