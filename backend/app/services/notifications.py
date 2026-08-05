import logging
import random

from app.config import get_settings
from app.ws.manager import ws_manager

settings = get_settings()

DAILY_REMINDER_POOL_FOR_HUSBAND = [
    "Your wife has memories and things waiting for you that will bring you joy — halal and yours alone.",
    "Something private and just for you is waiting in your vault.",
    "A quiet moment with your wife is one tap away.",
    "Your wife left something for you today — go take a look.",
    "There's a halal escape waiting for you, just open the app.",
    "Your other half has been thinking of you — check what's new.",
    "A little piece of your wife is waiting for you today.",
    "Something warm and just yours is sitting in the vault.",
    "Your wife's world is one tap away — go see what's new.",
    "Take a break and reconnect with your wife today.",
    "There's a reason to smile waiting in your app today.",
    "Your vault has something new from your wife.",
    "Distance is temporary — your wife's love isn't. Check the app.",
    "A halal moment of closeness is waiting for you.",
    "Your wife made sure there's something for you today.",
    "Come back to what's real — your wife is waiting.",
    "Something meant only for your eyes is in the vault today.",
    "Your marriage's private corner has something new.",
    "Reconnect with your wife instead of anywhere else — open the app.",
    "A small gift from your wife is waiting for you.",
    "Your wife's love doesn't need the internet's version — check yours.",
    "Something built just for the two of you is waiting.",
    "Your private world with your wife has new memories today.",
    "A halal alternative to loneliness is one tap away.",
    "Your wife thought of you today — see what she left.",
    "Come home to your wife, even from far away — open the app.",
]

DAILY_REMINDER_POOL_FOR_WIFE = [
    "Your husband has memories and things waiting for you that will bring you joy — halal and yours alone.",
    "Something private and just for you is waiting in your vault.",
    "A quiet moment with your husband is one tap away.",
    "Your husband left something for you today — go take a look.",
    "There's a halal escape waiting for you, just open the app.",
    "Your other half has been thinking of you — check what's new.",
    "A little piece of your husband is waiting for you today.",
    "Something warm and just yours is sitting in the vault.",
    "Your husband's world is one tap away — go see what's new.",
    "Take a break and reconnect with your husband today.",
    "There's a reason to smile waiting in your app today.",
    "Your vault has something new from your husband.",
    "Distance is temporary — your husband's love isn't. Check the app.",
    "A halal moment of closeness is waiting for you.",
    "Your husband made sure there's something for you today.",
    "Come back to what's real — your husband is waiting.",
    "Something meant only for your eyes is in the vault today.",
    "Your marriage's private corner has something new.",
    "Reconnect with your husband instead of anywhere else — open the app.",
    "A small gift from your husband is waiting for you.",
    "Your husband's love doesn't need the internet's version — check yours.",
    "Something built just for the two of you is waiting.",
    "Your private world with your husband has new memories today.",
    "A halal alternative to loneliness is one tap away.",
    "Your husband thought of you today — see what he left.",
    "Come home to your husband, even from far away — open the app.",
]


def pick_daily_message(role: str) -> str:
    pool = DAILY_REMINDER_POOL_FOR_HUSBAND if role == "husband" else DAILY_REMINDER_POOL_FOR_WIFE
    return random.choice(pool)


GENERIC_UPDATE_MESSAGE = "অ্যাপে একটা নতুন আপডেট এসেছে।"

# Push notification bodies must NEVER reveal anything from inside the app --
# no message text, no names, no counts that could hint at content. Only a
# generic, category-level phrase ("a text/photo/video arrived") is allowed.
# See DECISIONS.md and project.md §7. Keyed by notify_spouse's `category`,
# then optionally narrowed by `content_type` for categories where the app
# already knows that much (chat message kind, vault entry kind) without it
# revealing anything about the actual content.
_NOTIFICATION_TEXT: dict[str, dict[str, str]] = {
    "chat": {
        "text": "নতুন একটা মেসেজ এসেছে।",
        "photo": "নতুন একটা ছবি এসেছে।",
        "video": "নতুন একটা ভিডিও এসেছে।",
        "voice": "নতুন একটা ভয়েস মেসেজ এসেছে।",
        "_default": "নতুন একটা মেসেজ এসেছে।",
    },
    "content_new": {
        "text": "ভল্টে নতুন একটা লেখা যোগ হয়েছে।",
        "photo": "ভল্টে নতুন একটা ছবি যোগ হয়েছে।",
        "video": "ভল্টে নতুন একটা ভিডিও যোগ হয়েছে।",
        "_default": "ভল্টে নতুন কিছু যোগ হয়েছে।",
    },
    "content_edited": {"_default": "ভল্টের একটা এন্ট্রি এডিট হয়েছে।"},
    "content_deleted": {"_default": "ভল্টের একটা এন্ট্রি মুছে ফেলা হয়েছে।"},
    "reaction": {"_default": "তোমার কিছুতে একটা রিঅ্যাকশন এসেছে।"},
    "comment": {"_default": "তোমার কিছুতে নতুন একটা মন্তব্য এসেছে।"},
    "consent_request": {"_default": "একটা অনুমোদনের অনুরোধ এসেছে।"},
    "consent_resolved": {"_default": "তোমার একটা অনুরোধের সিদ্ধান্ত হয়েছে।"},
    "phrase": {"_default": "প্রিয় লাইনে নতুন কিছু যোগ হয়েছে।"},
}


def _notification_body(category: str, content_type: str | None) -> str:
    bucket = _NOTIFICATION_TEXT.get(category)
    if bucket is None:
        return GENERIC_UPDATE_MESSAGE
    if content_type and content_type in bucket:
        return bucket[content_type]
    return bucket.get("_default", GENERIC_UPDATE_MESSAGE)


async def notify_spouse(
    spouse_id_target: str,
    push_tokens: list[str],
    category: str = "update",
    content_type: str | None = None,
) -> None:
    """Send a real-time WS ping (if connected) and queue pushes for when the
    app isn't open.

    `category` (e.g. "reaction", "comment", "chat", "consent_request") and
    the optional `content_type` (e.g. "text"/"photo"/"video"/"voice") pick a
    pre-written, fully generic body from `_NOTIFICATION_TEXT` -- never the
    actual message/entry content. `category` alone still routes/collapses
    the WS event client-side same as before.
    """
    await ws_manager.send_to_spouse(spouse_id_target, {"type": category})
    if not push_tokens:
        return
    body = _notification_body(category, content_type)
    for token in push_tokens:
        await send_generic_push(token, body=body)


_firebase_app = None
_firebase_unavailable = False


def _firebase() -> "firebase_admin.App | None":  # noqa: F821 -- forward ref, imported lazily below
    """Lazily initializes (once) the Firebase Admin app from the service
    account file path in settings. Returns None -- silently -- if no path is
    configured or initialization fails, so push notifications degrade
    gracefully to "not sent" rather than ever breaking the request that
    triggered them (chat send, new vault entry, etc.)."""
    global _firebase_app, _firebase_unavailable
    if _firebase_app is not None or _firebase_unavailable:
        return _firebase_app
    if not settings.fcm_service_account_path:
        _firebase_unavailable = True
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials

        if firebase_admin._apps:
            _firebase_app = firebase_admin.get_app()
        else:
            _firebase_app = firebase_admin.initialize_app(
                credentials.Certificate(settings.fcm_service_account_path)
            )
    except Exception:
        logging.getLogger(__name__).exception("Failed to initialize Firebase Admin SDK")
        _firebase_unavailable = True
        _firebase_app = None
    return _firebase_app


async def send_generic_push(device_push_token: str, body: str | None = None) -> None:
    if not device_push_token:
        return
    app = _firebase()
    if app is None:
        return
    try:
        from firebase_admin import messaging
        from starlette.concurrency import run_in_threadpool

        message = messaging.Message(
            notification=messaging.Notification(title="পার্সোনাল", body=body or GENERIC_UPDATE_MESSAGE),
            token=device_push_token,
            android=messaging.AndroidConfig(priority="high"),
        )
        # messaging.send() is a blocking network call -- offload it so it
        # never stalls the event loop, same pattern as storage.py's MinIO
        # calls.
        await run_in_threadpool(messaging.send, message, app=app)
    except Exception:
        logging.getLogger(__name__).warning("Push send failed for a device token", exc_info=True)
