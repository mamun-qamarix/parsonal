import uuid

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
        # Swipe-to-reply: quote another message by id. Self-referential FK,
        # SET NULL on delete so replying to a since-deleted message just
        # drops the quote instead of failing. See DECISIONS.md.
        await conn.execute(text(
            "ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES chat_messages(id) ON DELETE SET NULL"
        ))
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
        # Setup codes became persistent/reusable instead of single-use (see
        # DECISIONS.md), with the Vault Master Key moved to its own
        # never-changes vault_keys table so regenerating a shareable code
        # can't ever produce a different key than devices already claimed
        # with. Backfill: if a deployment mid-setup (one role claimed, code
        # still around) already has a vmk on its setup_codes row, carry
        # THAT SAME key into vault_keys rather than generating a new one --
        # a deployment that already fully deleted its code (both roles
        # claimed before this update) has no recoverable key here; the
        # admin panel warns about that case explicitly.
        has_vault_key = await conn.execute(text("SELECT 1 FROM vault_keys LIMIT 1"))
        if has_vault_key.first() is None:
            existing_code_key = await conn.execute(text("SELECT vmk_encrypted FROM setup_codes ORDER BY created_at ASC LIMIT 1"))
            row = existing_code_key.first()
            if row is not None:
                await conn.execute(
                    text("INSERT INTO vault_keys (id, vmk_encrypted, created_at) VALUES (:id, :vmk, now())"),
                    {"id": uuid.uuid4(), "vmk": row[0]},
                )
