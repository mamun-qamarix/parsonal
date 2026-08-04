from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from fastapi.responses import StreamingResponse
import io
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.deps import get_current_spouse
from app.models.media import MediaAsset, MediaKindEnum
from app.models.user import Spouse
from app.schemas.content import MediaAssetOut
from app.services import storage

router = APIRouter(prefix="/media", tags=["media"])
settings = get_settings()


def _upload_size(f: UploadFile) -> int:
    if f.size is not None:
        return f.size
    f.file.seek(0, 2)
    size = f.file.tell()
    f.file.seek(0)
    return size


@router.post("/upload", response_model=MediaAssetOut)
async def upload_media(
    kind: str = Form(...),
    file: UploadFile = File(...),
    thumbnail: UploadFile | None = File(default=None),
    spouse: Spouse = Depends(get_current_spouse),
    db: AsyncSession = Depends(get_db),
):
    if kind not in (k.value for k in MediaKindEnum):
        raise HTTPException(status_code=400, detail="Invalid media kind")

    max_bytes = settings.max_upload_mb * 1024 * 1024
    size = _upload_size(file)
    if size > max_bytes:
        raise HTTPException(status_code=413, detail=f"File exceeds {settings.max_upload_mb}MB limit")

    # Stream straight from the spooled upload file instead of reading it
    # all into a Python bytes object first -- with uploads up to 1GB now
    # allowed, that would double peak memory use for no reason. See
    # DECISIONS.md.
    object_key = await storage.put_object(file.file, length=size, content_type="application/octet-stream")

    thumb_key = None
    if thumbnail is not None:
        thumb_size = _upload_size(thumbnail)
        thumb_key = await storage.put_object(thumbnail.file, length=thumb_size, content_type="application/octet-stream")

    asset = MediaAsset(kind=MediaKindEnum(kind), object_key=object_key, thumbnail_object_key=thumb_key, size_bytes=size)
    db.add(asset)
    await db.commit()
    await db.refresh(asset)
    return MediaAssetOut(id=asset.id, kind=asset.kind.value, size_bytes=asset.size_bytes, has_thumbnail=thumb_key is not None)


async def _stream_object(object_key: str):
    try:
        data = await storage.get_object(object_key)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Object not found")
    return StreamingResponse(io.BytesIO(data), media_type="application/octet-stream")


@router.get("/{asset_id}/raw")
async def get_media_raw(asset_id: str, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(MediaAsset).where(MediaAsset.id == asset_id))
    asset = result.scalar_one_or_none()
    if asset is None:
        raise HTTPException(status_code=404, detail="Not found")
    return await _stream_object(asset.object_key)


@router.get("/{asset_id}/thumbnail")
async def get_media_thumbnail(asset_id: str, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(MediaAsset).where(MediaAsset.id == asset_id))
    asset = result.scalar_one_or_none()
    if asset is None or not asset.thumbnail_object_key:
        raise HTTPException(status_code=404, detail="No thumbnail")
    return await _stream_object(asset.thumbnail_object_key)
