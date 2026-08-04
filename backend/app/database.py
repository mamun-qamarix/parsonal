from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import get_settings

settings = get_settings()

engine = create_async_engine(settings.database_url, echo=False, future=True)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


class Base(DeclarativeBase):
    pass


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session


async def init_models():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # create_all() only creates missing tables, never alters existing
        # ones -- these are lightweight, idempotent patches for columns
        # added after a table already existed on a live deployment, so a
        # full database reset isn't required for every schema tweak.
        await conn.execute(text("ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_uuid VARCHAR(64)"))
        # TOTP moved from spouses (shared per role) to devices (per
        # physical device) -- see DECISIONS.md. The old spouses.totp_secret
        # / totp_confirmed columns are left in place, unused, on deployments
        # that already have them; new deployments never create them since
        # they're no longer on the Spouse model.
        await conn.execute(text("ALTER TABLE devices ADD COLUMN IF NOT EXISTS totp_secret VARCHAR(64)"))
        await conn.execute(text("ALTER TABLE devices ADD COLUMN IF NOT EXISTS totp_confirmed BOOLEAN NOT NULL DEFAULT FALSE"))
        # One-time backfill for deployments that had the old spouses-level
        # totp_secret/totp_confirmed: copy it onto every existing Device row
        # for that spouse, so already-set-up authenticator entries on
        # already-working phones keep working instead of everyone having to
        # redo TOTP setup after this update. Brand-new deployments never had
        # those spouses columns at all (guard against that).
        has_old_column = await conn.execute(text(
            "SELECT 1 FROM information_schema.columns WHERE table_name = 'spouses' AND column_name = 'totp_secret'"
        ))
        if has_old_column.first() is not None:
            await conn.execute(text(
                """
                UPDATE devices d SET totp_secret = s.totp_secret, totp_confirmed = s.totp_confirmed
                FROM spouses s
                WHERE d.spouse_id = s.id AND d.totp_secret IS NULL AND s.totp_secret IS NOT NULL
                """
            ))
