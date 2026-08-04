import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse
from app.models.audit import AuditLogEntry
from app.models.user import Spouse, Device
from app.schemas.device import DeviceOut

router = APIRouter(tags=["device"])


class PushTokenUpdate(BaseModel):
    push_token: str


@router.put("/device/push-token")
async def update_push_token(payload: PushTokenUpdate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Device).where(Device.spouse_id == spouse.id).order_by(Device.created_at.desc()))
    device = result.scalars().first()
    if device is None:
        return {"ok": False, "detail": "No device found for this session"}
    device.push_token = payload.push_token
    await db.commit()
    return {"ok": True}


@router.get("/devices", response_model=list[DeviceOut])
async def list_devices(
    current_device_id: uuid.UUID | None = None,
    spouse: Spouse = Depends(get_current_spouse),
    db: AsyncSession = Depends(get_db),
):
    """Every registered device across BOTH spouses -- either of you can see
    and revoke any device (e.g. a lost/stolen phone), matching the app's
    shared-trust model. See DECISIONS.md #16."""
    result = await db.execute(
        select(Device, Spouse.role).join(Spouse, Spouse.id == Device.spouse_id).order_by(Device.last_seen_at.desc())
    )
    rows = result.all()
    return [
        DeviceOut(
            id=d.id,
            device_name=d.device_name,
            role=role.value,
            is_this_device=(current_device_id is not None and d.id == current_device_id),
            created_at=d.created_at,
            last_seen_at=d.last_seen_at,
        )
        for d, role in rows
    ]


@router.delete("/devices/{device_id}")
async def delete_device(device_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Device).where(Device.id == device_id))
    device = result.scalar_one_or_none()
    if device is None:
        raise HTTPException(status_code=404, detail="Device not found")
    db.add(AuditLogEntry(actor_id=spouse.id, action="device.remove", target_type="device", target_id=device.id, detail=device.device_name))
    await db.delete(device)
    await db.commit()
    return {"ok": True}
