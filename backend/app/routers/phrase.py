import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse, other_role
from app.models.phrase import Phrase, DirectionEnum
from app.models.user import Spouse, Device, RoleEnum
from app.schemas.common import b64_to_bytes, bytes_to_b64
from app.schemas.phrase import PhraseCreate, PhraseRate, PhraseOut
from app.services.notifications import notify_spouse

router = APIRouter(prefix="/phrases", tags=["phrases"])


def _role_of(spouse: Spouse) -> str:
    return spouse.role.value if hasattr(spouse.role, "value") else spouse.role


def _out(p: Phrase) -> PhraseOut:
    return PhraseOut(
        id=p.id, direction=p.direction.value, author_id=p.author_id, enc_payload=bytes_to_b64(p.enc_payload),
        rating_husband=p.rating_husband, rating_wife=p.rating_wife, created_at=p.created_at,
    )


@router.post("", response_model=PhraseOut)
async def create_phrase(payload: PhraseCreate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    if payload.direction not in (d.value for d in DirectionEnum):
        raise HTTPException(status_code=400, detail="Invalid direction")
    phrase = Phrase(direction=DirectionEnum(payload.direction), author_id=spouse.id, enc_payload=b64_to_bytes(payload.enc_payload))
    db.add(phrase)
    await db.commit()
    await db.refresh(phrase)

    target_role = other_role(_role_of(spouse))
    target_result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(target_role)))
    target = target_result.scalar_one_or_none()
    if target:
        tokens_result = await db.execute(select(Device.push_token).where(Device.spouse_id == target.id, Device.push_token.is_not(None)))
        tokens = [t for t in tokens_result.scalars().all() if t]
        await notify_spouse(str(target.id), tokens, category="phrase")

    return _out(phrase)


@router.get("", response_model=list[PhraseOut])
async def list_phrases(direction: str | None = None, sort_by_rating: bool = False, db: AsyncSession = Depends(get_db), spouse: Spouse = Depends(get_current_spouse)):
    query = select(Phrase)
    if direction:
        query = query.where(Phrase.direction == DirectionEnum(direction))
    result = await db.execute(query)
    phrases = result.scalars().all()
    if sort_by_rating:
        def avg_rating(p: Phrase) -> float:
            ratings = [r for r in (p.rating_husband, p.rating_wife) if r is not None]
            return sum(ratings) / len(ratings) if ratings else 0
        phrases = sorted(phrases, key=avg_rating, reverse=True)
    else:
        phrases = sorted(phrases, key=lambda p: p.created_at, reverse=True)
    return [_out(p) for p in phrases]


@router.post("/{phrase_id}/rate", response_model=PhraseOut)
async def rate_phrase(phrase_id: uuid.UUID, payload: PhraseRate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    if not (1 <= payload.rating <= 5):
        raise HTTPException(status_code=400, detail="rating must be between 1 and 5")
    result = await db.execute(select(Phrase).where(Phrase.id == phrase_id))
    phrase = result.scalar_one_or_none()
    if phrase is None:
        raise HTTPException(status_code=404, detail="Not found")

    if _role_of(spouse) == "husband":
        phrase.rating_husband = payload.rating
    else:
        phrase.rating_wife = payload.rating
    await db.commit()
    await db.refresh(phrase)
    return _out(phrase)


@router.delete("/{phrase_id}")
async def delete_phrase(phrase_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Phrase).where(Phrase.id == phrase_id))
    phrase = result.scalar_one_or_none()
    if phrase is None:
        raise HTTPException(status_code=404, detail="Not found")
    if phrase.author_id != spouse.id:
        raise HTTPException(status_code=403, detail="Only the author can delete this phrase")
    await db.delete(phrase)
    await db.commit()
    return {"ok": True}
