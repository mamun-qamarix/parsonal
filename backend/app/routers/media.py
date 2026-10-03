from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File, Form
from fastapi.responses import Response, StreamingResponse
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
    chunked: bool = Form(default=False),
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

    asset = MediaAsset(
        kind=MediaKindEnum(kind), object_key=object_key, thumbnail_object_key=thumb_key, size_bytes=size, chunked=chunked,
    )
    db.add(asset)
    await db.commit()
    await db.refresh(asset)
    return MediaAssetOut(id=asset.id, kind=asset.kind.value, size_bytes=asset.size_bytes, has_thumbnail=thumb_key is not None)


@router.put("/{asset_id}/thumbnail", response_model=MediaAssetOut)
async def attach_thumbnail(
    asset_id: str,
    thumbnail: UploadFile = File(...),
    spouse: Spouse = Depends(get_current_spouse),
    db: AsyncSession = Depends(get_db),
):
    """Backfills a thumbnail onto an already-uploaded video asset that
    doesn't have one yet -- either an entry from before client-side
    thumbnail generation existed, or one where generation silently failed
    on-device the first time. Called lazily by the client whenever it's
    about to display such a video, so old entries self-heal the first
    time anyone actually looks at them instead of needing a one-off
    migration. See DECISIONS.md."""
    result = await db.execute(select(MediaAsset).where(MediaAsset.id == asset_id))
    asset = result.scalar_one_or_none()
    if asset is None:
        raise HTTPException(status_code=404, detail="Not found")

    thumb_size = _upload_size(thumbnail)
    thumb_key = await storage.put_object(thumbnail.file, length=thumb_size, content_type="application/octet-stream")
    asset.thumbnail_object_key = thumb_key
    await db.commit()
    await db.refresh(asset)
    return MediaAssetOut(id=asset.id, kind=asset.kind.value, size_bytes=asset.size_bytes, has_thumbnail=True)


async def _stream_object(object_key: str):
    try:
        data = await storage.get_object(object_key)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Object not found")
    # Explicit Content-Length so the app can show real download progress
    # (a chunked StreamingResponse has no total size). See DECISIONS.md.
    return StreamingResponse(
        io.BytesIO(data),
        media_type="application/octet-stream",
        headers={"Content-Length": str(len(data)), "Accept-Ranges": "bytes"},
    )


# One range request never returns more than this, so a client asking for
# "bytes=0-" can't make the server load a whole 1GB object into memory.
_MAX_RANGE_BYTES = 32 * 1024 * 1024


def _parse_range(header: str, total: int) -> tuple[int, int]:
    """'bytes=a-b' / 'bytes=a-' / 'bytes=-n' -> inclusive (start, end)."""
    try:
        unit, spec = header.strip().split("=", 1)
        if unit.strip() != "bytes" or "," in spec:
            raise ValueError
        a, b = spec.strip().split("-", 1)
        if a == "":
            n = int(b)
            start, end = max(total - n, 0), total - 1
        else:
            start = int(a)
            end = int(b) if b else total - 1
    except ValueError:
        raise HTTPException(status_code=416, detail="Bad range")
    end = min(end, total - 1, start + _MAX_RANGE_BYTES - 1)
    if start < 0 or start > end:
        raise HTTPException(status_code=416, detail="Bad range", headers={"Content-Range": f"bytes */{total}"})
    return start, end


@router.get("/legacy-videos")
async def list_legacy_videos(spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Videos still in the old single-blob format (not streamable yet), for
    the app's one-time conversion screen. See DECISIONS.md."""
    result = await db.execute(
        select(MediaAsset).where(MediaAsset.kind == MediaKindEnum.video, MediaAsset.chunked == False)  # noqa: E712
    )
    return [{"id": str(a.id), "size_bytes": a.size_bytes} for a in result.scalars().all()]


@router.get("/{asset_id}/raw")
async def get_media_raw(
    asset_id: str,
    request: Request,
    spouse: Spouse = Depends(get_current_spouse),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(MediaAsset).where(MediaAsset.id == asset_id))
    asset = result.scalar_one_or_none()
    if asset is None:
        raise HTTPException(status_code=404, detail="Not found")
    range_header = request.headers.get("range")
    if not range_header:
        return await _stream_object(asset.object_key)
    # Range request: lets the app stream a video piece by piece instead of
    # downloading all of it before playback starts. See DECISIONS.md.
    try:
        total = await storage.object_size(asset.object_key)
        start, end = _parse_range(range_header, total)
        data = await storage.get_range(asset.object_key, start, end - start + 1)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Object not found")
    return Response(
        content=data,
        status_code=206,
        media_type="application/octet-stream",
        headers={
            "Content-Range": f"bytes {start}-{start + len(data) - 1}/{total}",
            "Accept-Ranges": "bytes",
        },
    )


@router.put("/{asset_id}/raw", response_model=MediaAssetOut)
async def replace_with_chunked(
    asset_id: str,
    file: UploadFile = File(...),
    spouse: Spouse = Depends(get_current_spouse),
    db: AsyncSession = Depends(get_db),
):
    """One-time conversion of an old single-blob video to the streamable
    chunked format (re-encrypted on the phone, the server still only sees
    ciphertext). The previous object is NOT deleted -- its key is kept in
    legacy_object_key -- per the "never remove media" rule."""
    result = await db.execute(select(MediaAsset).where(MediaAsset.id == asset_id))
    asset = result.scalar_one_or_none()
    if asset is None:
        raise HTTPException(status_code=404, detail="Not found")
    if asset.chunked:
        raise HTTPException(status_code=409, detail="Already converted")
    size = _upload_size(file)
    if size > settings.max_upload_mb * 1024 * 1024:
        raise HTTPException(status_code=413, detail=f"File exceeds {settings.max_upload_mb}MB limit")
    new_key = await storage.put_object(file.file, length=size, content_type="application/octet-stream")
    asset.legacy_object_key = asset.object_key
    asset.object_key = new_key
    asset.size_bytes = size
    asset.chunked = True
    await db.commit()
    await db.refresh(asset)
    return MediaAssetOut(
        id=asset.id, kind=asset.kind.value, size_bytes=asset.size_bytes, has_thumbnail=asset.thumbnail_object_key is not None,
    )


@router.get("/{asset_id}/thumbnail")
async def get_media_thumbnail(asset_id: str, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(MediaAsset).where(MediaAsset.id == asset_id))
    asset = result.scalar_one_or_none()
    if asset is None or not asset.thumbnail_object_key:
        raise HTTPException(status_code=404, detail="No thumbnail")
    return await _stream_object(asset.thumbnail_object_key)
