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


GENERIC_UPDATE_MESSAGE = "You have a new update in the app."


async def notify_spouse(spouse_id_target: str, push_tokens: list[str], category: str = "update") -> None:
    """Send a real-time WS ping (if connected) and queue generic pushes.

    `category` values (e.g. "reaction", "comment", "chat", "consent_request")
    are used only to route/collapse the WS event client-side; the push
    payload itself always stays generic per spec §7.
    """
    await ws_manager.send_to_spouse(spouse_id_target, {"type": category})
    for token in push_tokens:
        await send_generic_push(token)


async def send_generic_push(device_push_token: str, body: str | None = None) -> None:
    if not settings.fcm_server_key or not device_push_token:
        return
    try:
        import firebase_admin
        from firebase_admin import messaging, credentials

        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate({}))
        messaging.send(
            messaging.Message(
                notification=messaging.Notification(title="Vault", body=body or GENERIC_UPDATE_MESSAGE),
                token=device_push_token,
            )
        )
    except Exception:
        pass
