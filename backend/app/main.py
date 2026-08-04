import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import get_settings
from app.database import init_models
from app.services.scheduler import start_scheduler, stop_scheduler
from app.services.storage import ensure_bucket
from app.routers import auth, admin, content, media, social, chat, wishlist, phrase, profile, audit, reel, device

settings = get_settings()
logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_models()
    try:
        ensure_bucket()
    except Exception as exc:
        logging.getLogger(__name__).warning("MinIO not reachable at startup: %s", exc)
    start_scheduler()
    yield
    stop_scheduler()


app = FastAPI(title=settings.app_name, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/admin/static", StaticFiles(directory="admin_panel/static"), name="admin_static")

app.include_router(auth.router)
app.include_router(admin.router)
app.include_router(content.router)
app.include_router(media.router)
app.include_router(social.router)
app.include_router(chat.router)
app.include_router(wishlist.router)
app.include_router(phrase.router)
app.include_router(profile.router)
app.include_router(audit.router)
app.include_router(reel.router)
app.include_router(device.router)


@app.get("/health")
async def health():
    return {"status": "ok"}
