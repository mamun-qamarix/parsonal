import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse, other_role
from app.models.social import Reaction, Comment, Favorite, MatchCelebrationSeen
from app.models.user import Spouse, Device, RoleEnum
from app.models.audit import AuditLogEntry
from app.schemas.common import b64_to_bytes, bytes_to_b64, ReactionBreakdown
from app.schemas.social import ReactionCreate, CommentCreate, CommentOut, FavoriteToggle
from app.services.notifications import notify_spouse

router = APIRouter(tags=["social"])

VALID_TARGET_TYPES = {"vault_entry", "comment", "chat_message", "phrase"}


async def _push_tokens_for_role(db: AsyncSession, role: str) -> list[str]:
    result = await db.execute(
        select(Device.push_token).join(Spouse, Spouse.id == Device.spouse_id).where(Spouse.role == RoleEnum(role), Device.push_token.is_not(None))
    )
    return [t for t in result.scalars().all() if t]


async def _notify_other_spouse(db: AsyncSession, my_role: str, category: str) -> None:
    target_role = other_role(my_role)
    result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(target_role)))
    target = result.scalar_one_or_none()
    if target is None:
        return
    tokens = await _push_tokens_for_role(db, target_role)
    await notify_spouse(str(target.id), tokens, category=category)


def _role_of(spouse: Spouse) -> str:
    return spouse.role.value if hasattr(spouse.role, "value") else spouse.role


# ---------- Reactions ----------

@router.post("/reactions")
async def add_reaction(payload: ReactionCreate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    if payload.target_type not in VALID_TARGET_TYPES:
        raise HTTPException(status_code=400, detail="Invalid target_type")
    if payload.target_type == "comment" and payload.emoji != "❤️" and payload.emoji != "❤":
        raise HTTPException(status_code=400, detail="Comments only support the heart reaction")

    existing = await db.execute(
        select(Reaction).where(
            Reaction.target_type == payload.target_type,
            Reaction.target_id == payload.target_id,
            Reaction.spouse_id == spouse.id,
            Reaction.emoji == payload.emoji,
        )
    )
    if existing.scalar_one_or_none():
        return {"ok": True, "already_reacted": True}

    db.add(Reaction(target_type=payload.target_type, target_id=payload.target_id, spouse_id=spouse.id, emoji=payload.emoji))
    db.add(AuditLogEntry(actor_id=spouse.id, action="reaction.add", target_type=payload.target_type, target_id=payload.target_id, detail=payload.emoji))
    await db.commit()

    await _notify_other_spouse(db, _role_of(spouse), "reaction")

    match_formed = await _check_match(db, payload.target_type, payload.target_id)
    return {"ok": True, "already_reacted": False, "match_formed": match_formed}


@router.delete("/reactions")
async def remove_reaction(payload: ReactionCreate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Reaction).where(
            Reaction.target_type == payload.target_type,
            Reaction.target_id == payload.target_id,
            Reaction.spouse_id == spouse.id,
            Reaction.emoji == payload.emoji,
        )
    )
    reaction = result.scalar_one_or_none()
    if reaction:
        await db.delete(reaction)
        await db.commit()
    return {"ok": True}


@router.get("/reactions/{target_type}/{target_id}", response_model=list[ReactionBreakdown])
async def get_reaction_breakdown(target_type: str, target_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Reaction, Spouse.role).join(Spouse, Spouse.id == Reaction.spouse_id).where(
            Reaction.target_type == target_type, Reaction.target_id == target_id
        )
    )
    rows = result.all()
    by_emoji: dict[str, dict] = {}
    for reaction, role in rows:
        entry = by_emoji.setdefault(reaction.emoji, {"husband_count": 0, "wife_count": 0, "reacted_by_me": False})
        if role == RoleEnum.husband:
            entry["husband_count"] += 1
        else:
            entry["wife_count"] += 1
        if reaction.spouse_id == spouse.id:
            entry["reacted_by_me"] = True

    return [ReactionBreakdown(emoji=e, husband_count=v["husband_count"], wife_count=v["wife_count"], reacted_by_me=v["reacted_by_me"]) for e, v in by_emoji.items()]


async def _check_match(db: AsyncSession, target_type: str, target_id: uuid.UUID) -> bool:
    """A 'match' is both spouses having reacted with the heart emoji to the same target."""
    if target_type != "vault_entry":
        return False
    result = await db.execute(
        select(Spouse.role).join(Reaction, Reaction.spouse_id == Spouse.id).where(
            Reaction.target_type == target_type, Reaction.target_id == target_id, Reaction.emoji.in_(["❤️", "❤"])
        )
    )
    roles = {r for r in result.scalars().all()}
    return RoleEnum.husband in roles and RoleEnum.wife in roles


@router.get("/reactions/{target_type}/{target_id}/match-celebration")
async def get_match_celebration(target_type: str, target_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    is_match = await _check_match(db, target_type, target_id)
    if not is_match:
        return {"show_celebration": False}

    seen_result = await db.execute(
        select(MatchCelebrationSeen).where(
            MatchCelebrationSeen.spouse_id == spouse.id, MatchCelebrationSeen.target_type == target_type, MatchCelebrationSeen.target_id == target_id
        )
    )
    if seen_result.scalar_one_or_none():
        return {"show_celebration": False}

    db.add(MatchCelebrationSeen(spouse_id=spouse.id, target_type=target_type, target_id=target_id))
    await db.commit()
    return {"show_celebration": True}


# ---------- Comments ----------

@router.post("/comments", response_model=CommentOut)
async def add_comment(payload: CommentCreate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    if payload.target_type not in VALID_TARGET_TYPES:
        raise HTTPException(status_code=400, detail="Invalid target_type")

    comment = Comment(target_type=payload.target_type, target_id=payload.target_id, author_id=spouse.id, enc_payload=b64_to_bytes(payload.enc_payload))
    db.add(comment)
    db.add(AuditLogEntry(actor_id=spouse.id, action="comment.add", target_type=payload.target_type, target_id=payload.target_id))
    await db.commit()
    await db.refresh(comment)

    await _notify_other_spouse(db, _role_of(spouse), "comment")

    return CommentOut(
        id=comment.id, target_type=comment.target_type, target_id=comment.target_id, author_id=comment.author_id,
        author_role=_role_of(spouse), enc_payload=bytes_to_b64(comment.enc_payload), created_at=comment.created_at,
        heart_count=0, hearted_by_me=False,
    )


@router.get("/comments/{target_type}/{target_id}", response_model=list[CommentOut])
async def list_comments(target_type: str, target_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Comment, Spouse.role).join(Spouse, Spouse.id == Comment.author_id).where(
            Comment.target_type == target_type, Comment.target_id == target_id
        ).order_by(Comment.created_at)
    )
    rows = result.all()
    out = []
    for comment, role in rows:
        heart_result = await db.execute(
            select(Reaction).where(Reaction.target_type == "comment", Reaction.target_id == comment.id, Reaction.emoji.in_(["❤️", "❤"]))
        )
        hearts = heart_result.scalars().all()
        out.append(CommentOut(
            id=comment.id, target_type=comment.target_type, target_id=comment.target_id, author_id=comment.author_id,
            author_role=role.value, enc_payload=bytes_to_b64(comment.enc_payload), created_at=comment.created_at,
            heart_count=len(hearts), hearted_by_me=any(h.spouse_id == spouse.id for h in hearts),
        ))
    return out


# ---------- Favorites (generic, e.g. for phrases; vault entries use /vault/entries/{id}/favorite) ----------

@router.post("/favorites/toggle")
async def toggle_favorite_generic(payload: FavoriteToggle, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Favorite).where(Favorite.spouse_id == spouse.id, Favorite.target_type == payload.target_type, Favorite.target_id == payload.target_id)
    )
    fav = result.scalar_one_or_none()
    if fav:
        await db.delete(fav)
        await db.commit()
        return {"is_favorite": False}
    db.add(Favorite(spouse_id=spouse.id, target_type=payload.target_type, target_id=payload.target_id))
    await db.commit()
    return {"is_favorite": True}
