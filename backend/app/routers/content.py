import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse, other_role
from app.models.content import Category, VaultEntry, ContentTypeEnum
from app.models.media import MediaAsset
from app.models.consent import ConsentRequest, ConsentActionEnum, ConsentStatusEnum
from app.models.social import Favorite
from app.models.audit import AuditLogEntry, ContentView
from app.models.user import Spouse, Device, RoleEnum
from app.models.common import utcnow
from app.schemas.common import b64_to_bytes, bytes_to_b64
from app.schemas.content import (
    CategoryCreate, CategoryOut, VaultEntryCreate, VaultEntryEdit, VaultEntryOut, MediaAssetOut,
    EditRequestCreate, ConsentRequestOut, ConsentDecision,
)
from app.services.notifications import notify_spouse

router = APIRouter(tags=["content"])


async def _push_tokens_for_role(db: AsyncSession, role: str) -> list[str]:
    result = await db.execute(
        select(Device.push_token).join(Spouse, Spouse.id == Device.spouse_id).where(Spouse.role == RoleEnum(role), Device.push_token.is_not(None))
    )
    return [t for t in result.scalars().all() if t]


async def _notify_other_spouse(db: AsyncSession, my_role: str, category: str, content_type: str | None = None) -> None:
    target_role = other_role(my_role)
    result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(target_role)))
    target = result.scalar_one_or_none()
    if target is None:
        return
    tokens = await _push_tokens_for_role(db, target_role)
    await notify_spouse(str(target.id), tokens, category=category, content_type=content_type)


# ---------- Categories ----------

@router.post("/categories", response_model=CategoryOut)
async def create_category(payload: CategoryCreate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    if payload.scope not in ("vault", "wishlist"):
        raise HTTPException(status_code=400, detail="scope must be 'vault' or 'wishlist'")
    cat = Category(scope=payload.scope, enc_name=b64_to_bytes(payload.enc_payload), created_by=spouse.id)
    db.add(cat)
    await db.commit()
    await db.refresh(cat)
    return CategoryOut(id=cat.id, scope=cat.scope, enc_name=bytes_to_b64(cat.enc_name), created_by=cat.created_by, created_at=cat.created_at)


@router.get("/categories", response_model=list[CategoryOut])
async def list_categories(scope: str = Query(...), db: AsyncSession = Depends(get_db), spouse: Spouse = Depends(get_current_spouse)):
    result = await db.execute(select(Category).where(Category.scope == scope).order_by(Category.created_at))
    cats = result.scalars().all()
    return [CategoryOut(id=c.id, scope=c.scope, enc_name=bytes_to_b64(c.enc_name), created_by=c.created_by, created_at=c.created_at) for c in cats]


# ---------- Vault entries ----------

def _role_of(spouse: Spouse) -> str:
    return spouse.role.value if hasattr(spouse.role, "value") else spouse.role


async def _entry_to_out(db: AsyncSession, entry: VaultEntry, viewer: Spouse) -> VaultEntryOut:
    author_result = await db.execute(select(Spouse).where(Spouse.id == entry.author_id))
    author = author_result.scalar_one()

    fav_result = await db.execute(
        select(Favorite).where(Favorite.spouse_id == viewer.id, Favorite.target_type == "vault_entry", Favorite.target_id == entry.id)
    )
    is_fav = fav_result.scalar_one_or_none() is not None

    view_count_result = await db.execute(select(func.count()).select_from(ContentView).where(ContentView.entry_id == entry.id))
    view_count = view_count_result.scalar_one()

    media_result = await db.execute(select(MediaAsset).where(MediaAsset.entry_id == entry.id))
    media_assets = [
        MediaAssetOut(id=m.id, kind=m.kind.value, size_bytes=m.size_bytes, has_thumbnail=m.thumbnail_object_key is not None)
        for m in media_result.scalars().all()
    ]

    return VaultEntryOut(
        id=entry.id, content_type=entry.content_type.value, category_id=entry.category_id,
        author_id=entry.author_id, author_role=author.role.value, enc_payload=bytes_to_b64(entry.enc_payload),
        created_at=entry.created_at, updated_at=entry.updated_at, is_favorite_mine=is_fav,
        view_count=view_count, media_assets=media_assets,
    )


@router.post("/vault/entries", response_model=VaultEntryOut)
async def create_entry(payload: VaultEntryCreate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    if payload.content_type not in (c.value for c in ContentTypeEnum):
        raise HTTPException(status_code=400, detail="Invalid content_type")

    entry = VaultEntry(
        content_type=ContentTypeEnum(payload.content_type),
        category_id=payload.category_id,
        author_id=spouse.id,
        enc_payload=b64_to_bytes(payload.enc_payload),
    )
    db.add(entry)
    await db.flush()

    if payload.media_asset_ids:
        result = await db.execute(select(MediaAsset).where(MediaAsset.id.in_(payload.media_asset_ids)))
        for asset in result.scalars().all():
            asset.entry_id = entry.id

    db.add(AuditLogEntry(actor_id=spouse.id, action="content.create", target_type="vault_entry", target_id=entry.id, detail=payload.content_type))
    await db.commit()
    await db.refresh(entry)

    await _notify_other_spouse(db, _role_of(spouse), "content_new", content_type=payload.content_type)
    return await _entry_to_out(db, entry, spouse)


@router.get("/vault/entries", response_model=list[VaultEntryOut])
async def list_entries(
    author_role: str | None = None,
    content_type: str | None = None,
    category_id: uuid.UUID | None = None,
    favorites_only: bool = False,
    limit: int = 100,
    offset: int = 0,
    spouse: Spouse = Depends(get_current_spouse),
    db: AsyncSession = Depends(get_db),
):
    query = select(VaultEntry).where(VaultEntry.is_deleted == False)  # noqa: E712
    if content_type:
        query = query.where(VaultEntry.content_type == ContentTypeEnum(content_type))
    if category_id:
        query = query.where(VaultEntry.category_id == category_id)
    if author_role:
        author_result = await db.execute(select(Spouse.id).where(Spouse.role == RoleEnum(author_role)))
        author_id = author_result.scalar_one_or_none()
        query = query.where(VaultEntry.author_id == author_id)

    query = query.order_by(VaultEntry.created_at.desc()).offset(offset).limit(limit)
    result = await db.execute(query)
    entries = result.scalars().all()

    out = [await _entry_to_out(db, e, spouse) for e in entries]
    if favorites_only:
        out = [o for o in out if o.is_favorite_mine]
    return out


@router.get("/vault/entries/{entry_id}", response_model=VaultEntryOut)
async def get_entry(entry_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(VaultEntry).where(VaultEntry.id == entry_id, VaultEntry.is_deleted == False))  # noqa: E712
    entry = result.scalar_one_or_none()
    if entry is None:
        raise HTTPException(status_code=404, detail="Not found")

    db.add(ContentView(entry_id=entry.id, viewer_id=spouse.id))
    db.add(AuditLogEntry(actor_id=spouse.id, action="content.view", target_type="vault_entry", target_id=entry.id))
    await db.commit()

    return await _entry_to_out(db, entry, spouse)


@router.put("/vault/entries/{entry_id}", response_model=VaultEntryOut)
async def edit_entry(entry_id: uuid.UUID, payload: VaultEntryEdit, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Edits an entry's text/category immediately -- no spouse approval,
    unlike the older edit-request/consent flow below (kept for now but no
    longer used by the client). The user explicitly asked for edit/delete
    to not require the other spouse's sign-off, at least for now. See
    DECISIONS.md."""
    result = await db.execute(select(VaultEntry).where(VaultEntry.id == entry_id, VaultEntry.is_deleted == False))  # noqa: E712
    entry = result.scalar_one_or_none()
    if entry is None:
        raise HTTPException(status_code=404, detail="Not found")

    entry.enc_payload = b64_to_bytes(payload.enc_payload)
    if payload.category_id is not None:
        entry.category_id = payload.category_id
    db.add(AuditLogEntry(actor_id=spouse.id, action="content.edit", target_type="vault_entry", target_id=entry.id))
    await db.commit()
    await db.refresh(entry)

    await _notify_other_spouse(db, _role_of(spouse), "content_edited", content_type=entry.content_type.value)
    return await _entry_to_out(db, entry, spouse)


@router.delete("/vault/entries/{entry_id}")
async def delete_entry(entry_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Soft-deletes an entry immediately -- no spouse approval. See
    edit_entry's note above and DECISIONS.md."""
    result = await db.execute(select(VaultEntry).where(VaultEntry.id == entry_id, VaultEntry.is_deleted == False))  # noqa: E712
    entry = result.scalar_one_or_none()
    if entry is None:
        raise HTTPException(status_code=404, detail="Not found")

    entry.is_deleted = True
    db.add(AuditLogEntry(actor_id=spouse.id, action="content.delete", target_type="vault_entry", target_id=entry.id))
    await db.commit()

    await _notify_other_spouse(db, _role_of(spouse), "content_deleted")
    return {"ok": True}


@router.post("/vault/entries/{entry_id}/favorite")
async def toggle_favorite(entry_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Favorite).where(Favorite.spouse_id == spouse.id, Favorite.target_type == "vault_entry", Favorite.target_id == entry_id)
    )
    fav = result.scalar_one_or_none()
    if fav:
        await db.delete(fav)
        await db.commit()
        return {"is_favorite": False}
    db.add(Favorite(spouse_id=spouse.id, target_type="vault_entry", target_id=entry_id))
    await db.commit()
    return {"is_favorite": True}


@router.post("/vault/entries/{entry_id}/edit-request", response_model=ConsentRequestOut)
async def request_edit(entry_id: uuid.UUID, payload: EditRequestCreate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    entry_result = await db.execute(select(VaultEntry).where(VaultEntry.id == entry_id, VaultEntry.is_deleted == False))  # noqa: E712
    if entry_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Entry not found")

    req = ConsentRequest(
        entry_id=entry_id, action=ConsentActionEnum.edit, requested_by=spouse.id,
        new_enc_payload=b64_to_bytes(payload.enc_payload),
    )
    db.add(req)
    db.add(AuditLogEntry(actor_id=spouse.id, action="content.edit_request", target_type="vault_entry", target_id=entry_id))
    await db.commit()
    await db.refresh(req)

    await _notify_other_spouse(db, _role_of(spouse), "consent_request")
    return ConsentRequestOut(id=req.id, entry_id=req.entry_id, action=req.action.value, requested_by=req.requested_by, status=req.status.value, created_at=req.created_at)


@router.post("/vault/entries/{entry_id}/delete-request", response_model=ConsentRequestOut)
async def request_delete(entry_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    entry_result = await db.execute(select(VaultEntry).where(VaultEntry.id == entry_id, VaultEntry.is_deleted == False))  # noqa: E712
    if entry_result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Entry not found")

    req = ConsentRequest(entry_id=entry_id, action=ConsentActionEnum.delete, requested_by=spouse.id)
    db.add(req)
    db.add(AuditLogEntry(actor_id=spouse.id, action="content.delete_request", target_type="vault_entry", target_id=entry_id))
    await db.commit()
    await db.refresh(req)

    await _notify_other_spouse(db, _role_of(spouse), "consent_request")
    return ConsentRequestOut(id=req.id, entry_id=req.entry_id, action=req.action.value, requested_by=req.requested_by, status=req.status.value, created_at=req.created_at)


@router.get("/vault/consent-requests", response_model=list[ConsentRequestOut])
async def list_consent_requests(status: str = "pending", spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    query = select(ConsentRequest)
    if status:
        query = query.where(ConsentRequest.status == ConsentStatusEnum(status))
    query = query.order_by(ConsentRequest.created_at.desc())
    result = await db.execute(query)
    reqs = result.scalars().all()
    return [ConsentRequestOut(id=r.id, entry_id=r.entry_id, action=r.action.value, requested_by=r.requested_by, status=r.status.value, created_at=r.created_at) for r in reqs]


@router.post("/vault/consent-requests/{request_id}/decide")
async def decide_consent_request(request_id: uuid.UUID, decision: ConsentDecision, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(ConsentRequest).where(ConsentRequest.id == request_id))
    req = result.scalar_one_or_none()
    if req is None:
        raise HTTPException(status_code=404, detail="Request not found")
    if req.status != ConsentStatusEnum.pending:
        raise HTTPException(status_code=409, detail="Request already resolved")
    if req.requested_by == spouse.id:
        raise HTTPException(status_code=403, detail="The requester cannot approve their own request")

    entry_result = await db.execute(select(VaultEntry).where(VaultEntry.id == req.entry_id))
    entry = entry_result.scalar_one_or_none()
    if entry is None:
        raise HTTPException(status_code=404, detail="Target entry not found")

    if decision.approve:
        if req.action == ConsentActionEnum.edit:
            entry.enc_payload = req.new_enc_payload
        elif req.action == ConsentActionEnum.delete:
            entry.is_deleted = True
        req.status = ConsentStatusEnum.approved
        action_label = f"content.{req.action.value}_approve"
    else:
        req.status = ConsentStatusEnum.rejected
        action_label = f"content.{req.action.value}_reject"

    req.resolved_by = spouse.id
    req.resolved_at = utcnow()
    db.add(AuditLogEntry(actor_id=spouse.id, action=action_label, target_type="vault_entry", target_id=entry.id))
    await db.commit()

    await _notify_other_spouse(db, _role_of(spouse), "consent_resolved")
    return {"status": req.status.value}
