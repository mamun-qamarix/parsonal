from fastapi import APIRouter, Depends
from sqlalchemy import select, func, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse
from app.models.notification import NotificationLog
from app.models.user import Spouse
from app.models.common import utcnow
from app.schemas.notification import NotificationOut, UnreadCountOut
from app.services.notifications import notification_body

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=list[NotificationOut])
async def list_notifications(
    limit: int = 50,
    spouse: Spouse = Depends(get_current_spouse),
    db: AsyncSession = Depends(get_db),
):
    """The in-app notification inbox -- newest first. Body text is
    rendered on read from category/content_type (see notification_body()),
    never stored pre-rendered, matching the same fully-generic, never-
    leaks-content wording used for push notifications."""
    result = await db.execute(
        select(NotificationLog)
        .where(NotificationLog.recipient_id == spouse.id)
        .order_by(NotificationLog.created_at.desc())
        .limit(limit)
    )
    rows = result.scalars().all()
    return [
        NotificationOut(
            id=n.id, category=n.category, content_type=n.content_type,
            body=notification_body(n.category, n.content_type),
            created_at=n.created_at, read_at=n.read_at,
        )
        for n in rows
    ]


@router.get("/unread-count", response_model=UnreadCountOut)
async def unread_count(spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(func.count()).select_from(NotificationLog).where(
            NotificationLog.recipient_id == spouse.id, NotificationLog.read_at.is_(None)
        )
    )
    return UnreadCountOut(unread_count=result.scalar_one())


@router.post("/mark-all-read")
async def mark_all_read(spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    await db.execute(
        update(NotificationLog)
        .where(NotificationLog.recipient_id == spouse.id, NotificationLog.read_at.is_(None))
        .values(read_at=utcnow())
    )
    await db.commit()
    return {"ok": True}
