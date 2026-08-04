from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse
from app.models.user import Spouse, Device

router = APIRouter(prefix="/device", tags=["device"])


class PushTokenUpdate(BaseModel):
    push_token: str


@router.put("/push-token")
async def update_push_token(payload: PushTokenUpdate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Device).where(Device.spouse_id == spouse.id).order_by(Device.created_at.desc()))
    device = result.scalars().first()
    if device is None:
        return {"ok": False, "detail": "No device found for this session"}
    device.push_token = payload.push_token
    await db.commit()
    return {"ok": True}
