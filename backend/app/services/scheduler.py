import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models.user import Spouse, Device, RoleEnum
from app.services.notifications import pick_daily_message, send_generic_push
from app.ws.manager import ws_manager

logger = logging.getLogger(__name__)
scheduler = AsyncIOScheduler()


async def send_daily_reminders() -> None:
    async with AsyncSessionLocal() as db:
        for role in (RoleEnum.husband, RoleEnum.wife):
            result = await db.execute(select(Spouse).where(Spouse.role == role))
            spouse = result.scalar_one_or_none()
            if spouse is None:
                continue
            message = pick_daily_message(role.value)
            await ws_manager.send_to_spouse(str(spouse.id), {"type": "daily_reminder", "message": message})

            tokens_result = await db.execute(select(Device.push_token).where(Device.spouse_id == spouse.id, Device.push_token.is_not(None)))
            for token in tokens_result.scalars().all():
                if token:
                    await send_generic_push(token, body=message)
            logger.info("Sent daily reminder to %s", role.value)


def start_scheduler() -> None:
    scheduler.add_job(send_daily_reminders, "cron", hour=9, minute=0, id="daily_reminder", replace_existing=True)
    scheduler.start()


def stop_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
