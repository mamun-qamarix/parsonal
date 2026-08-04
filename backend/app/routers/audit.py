from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse
from app.models.audit import AuditLogEntry, ContentView
from app.models.user import Spouse
from app.schemas.audit import AuditLogOut, ContentViewOut

router = APIRouter(prefix="/audit", tags=["audit"])


@router.get("/log", response_model=list[AuditLogOut])
async def get_audit_log(limit: int = 200, offset: int = 0, db: AsyncSession = Depends(get_db), spouse: Spouse = Depends(get_current_spouse)):
    result = await db.execute(select(AuditLogEntry).order_by(AuditLogEntry.created_at.desc()).offset(offset).limit(limit))
    return result.scalars().all()


@router.get("/views", response_model=list[ContentViewOut])
async def get_content_views(entry_id: str | None = None, limit: int = 200, db: AsyncSession = Depends(get_db), spouse: Spouse = Depends(get_current_spouse)):
    query = select(ContentView).order_by(ContentView.created_at.desc()).limit(limit)
    if entry_id:
        query = query.where(ContentView.entry_id == entry_id)
    result = await db.execute(query)
    return result.scalars().all()
