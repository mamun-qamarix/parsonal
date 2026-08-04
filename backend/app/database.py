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
