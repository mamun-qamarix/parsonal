import uuid

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse
from app.models.content import VaultEntry, ContentTypeEnum
from app.models.social import Favorite
from app.models.user import Spouse
from app.routers.content import _entry_to_out
from app.routers.social import _check_match

router = APIRouter(prefix="/reel", tags=["reel"])


@router.get("/feed")
async def get_reel_feed(
    favorites_only: bool = False,
    category_id: uuid.UUID | None = None,
    limit: int = 50,
    offset: int = 0,
    spouse: Spouse = Depends(get_current_spouse),
    db: AsyncSession = Depends(get_db),
):
    query = select(VaultEntry).where(
        VaultEntry.is_deleted == False,  # noqa: E712
        VaultEntry.content_type.in_([ContentTypeEnum.photo, ContentTypeEnum.video]),
    )
    if category_id:
        query = query.where(VaultEntry.category_id == category_id)
    query = query.order_by(VaultEntry.created_at.desc()).offset(offset).limit(limit)
    result = await db.execute(query)
    entries = result.scalars().all()

    items = []
    for entry in entries:
        out = await _entry_to_out(db, entry, spouse)
        if favorites_only and not out.is_favorite_mine:
            continue
        is_match = await _check_match(db, "vault_entry", entry.id)
        items.append({"entry": out.model_dump(), "is_match": is_match})
    return items
