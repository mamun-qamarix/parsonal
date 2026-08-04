import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse
from app.models.wishlist import WishlistItem
from app.models.user import Spouse, RoleEnum
from app.schemas.common import b64_to_bytes, bytes_to_b64
from app.schemas.wishlist import WishlistItemCreate, WishlistItemUpdate, WishlistItemOut

router = APIRouter(prefix="/wishlist", tags=["wishlist"])


def _out(item: WishlistItem) -> WishlistItemOut:
    return WishlistItemOut(
        id=item.id, owner_id=item.owner_id, category_id=item.category_id,
        enc_payload=bytes_to_b64(item.enc_payload), is_fulfilled=item.is_fulfilled, created_at=item.created_at,
    )


@router.post("", response_model=WishlistItemOut)
async def create_item(payload: WishlistItemCreate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    item = WishlistItem(owner_id=spouse.id, category_id=payload.category_id, enc_payload=b64_to_bytes(payload.enc_payload))
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return _out(item)


@router.get("", response_model=list[WishlistItemOut])
async def list_items(owner_role: str | None = None, db: AsyncSession = Depends(get_db), spouse: Spouse = Depends(get_current_spouse)):
    query = select(WishlistItem)
    if owner_role:
        owner_result = await db.execute(select(Spouse.id).where(Spouse.role == RoleEnum(owner_role)))
        owner_id = owner_result.scalar_one_or_none()
        query = query.where(WishlistItem.owner_id == owner_id)
    query = query.order_by(WishlistItem.created_at.desc())
    result = await db.execute(query)
    return [_out(i) for i in result.scalars().all()]


@router.patch("/{item_id}", response_model=WishlistItemOut)
async def update_item(item_id: uuid.UUID, payload: WishlistItemUpdate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(WishlistItem).where(WishlistItem.id == item_id))
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=404, detail="Not found")
    if item.owner_id != spouse.id:
        raise HTTPException(status_code=403, detail="Only the owner can edit their wishlist item")

    if payload.enc_payload is not None:
        item.enc_payload = b64_to_bytes(payload.enc_payload)
    if payload.is_fulfilled is not None:
        item.is_fulfilled = payload.is_fulfilled
    if payload.category_id is not None:
        item.category_id = payload.category_id
    await db.commit()
    await db.refresh(item)
    return _out(item)


@router.delete("/{item_id}")
async def delete_item(item_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(WishlistItem).where(WishlistItem.id == item_id))
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=404, detail="Not found")
    if item.owner_id != spouse.id:
        raise HTTPException(status_code=403, detail="Only the owner can delete their wishlist item")
    await db.delete(item)
    await db.commit()
    return {"ok": True}
