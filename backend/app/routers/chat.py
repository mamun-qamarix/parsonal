import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import AsyncSessionLocal, get_db
from app.deps import get_current_spouse, other_role
from app.models.chat import ChatMessage, ChatContentTypeEnum
from app.models.media import MediaAsset
from app.models.user import Spouse, Device, RoleEnum
from app.models.common import utcnow
from app.schemas.chat import ChatMessageCreate, ChatMessageOut, ChatMediaOut
from app.services.security import decode_token_safe, TokenError
from app.services.notifications import notify_spouse
from app.ws.manager import ws_manager

router = APIRouter(tags=["chat"])


def _role_of(spouse: Spouse) -> str:
    return spouse.role.value if hasattr(spouse.role, "value") else spouse.role


async def _msg_to_out(db: AsyncSession, msg: ChatMessage) -> ChatMessageOut:
    sender_result = await db.execute(select(Spouse).where(Spouse.id == msg.sender_id))
    sender = sender_result.scalar_one()
    media_result = await db.execute(
        select(MediaAsset.id, MediaAsset.thumbnail_object_key).where(MediaAsset.chat_message_id == msg.id)
    )
    media_row = media_result.first()
    media_id = media_row[0] if media_row else None
    has_thumbnail = bool(media_row[1]) if media_row else False
    from app.schemas.common import bytes_to_b64
    return ChatMessageOut(
        id=msg.id, sender_id=msg.sender_id, sender_role=sender.role.value, content_type=msg.content_type.value,
        enc_payload=bytes_to_b64(msg.enc_payload), created_at=msg.created_at, delivered_at=msg.delivered_at,
        read_at=msg.read_at, media_asset_id=media_id, media_has_thumbnail=has_thumbnail,
        reply_to_id=msg.reply_to_id,
    )


async def _persist_message(db: AsyncSession, sender: Spouse, payload: ChatMessageCreate) -> ChatMessage:
    if payload.content_type not in (c.value for c in ChatContentTypeEnum):
        raise ValueError("Invalid content_type")

    from app.schemas.common import b64_to_bytes
    enc_bytes = b64_to_bytes(payload.enc_payload) if payload.enc_payload else None

    msg = ChatMessage(
        sender_id=sender.id, content_type=ChatContentTypeEnum(payload.content_type), enc_payload=enc_bytes,
        reply_to_id=payload.reply_to_id,
    )
    db.add(msg)
    await db.flush()

    if payload.media_asset_id:
        asset_result = await db.execute(select(MediaAsset).where(MediaAsset.id == payload.media_asset_id))
        asset = asset_result.scalar_one_or_none()
        if asset:
            asset.chat_message_id = msg.id

    await db.commit()
    await db.refresh(msg)
    return msg


@router.post("/chat/messages", response_model=ChatMessageOut)
async def send_message_rest(payload: ChatMessageCreate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    try:
        msg = await _persist_message(db, spouse, payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    target_role = other_role(_role_of(spouse))
    target_result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(target_role)))
    target = target_result.scalar_one_or_none()
    out = await _msg_to_out(db, msg)

    if target is not None:
        delivered = await ws_manager.send_to_spouse(str(target.id), {"type": "chat_message", "message": json.loads(out.model_dump_json())})
        if delivered:
            msg.delivered_at = utcnow()
            await db.commit()
        tokens_result = await db.execute(select(Device.push_token).where(Device.spouse_id == target.id, Device.push_token.is_not(None)))
        tokens = [t for t in tokens_result.scalars().all() if t]
        await notify_spouse(db, str(target.id), tokens, category="chat", content_type=payload.content_type)

    return await _msg_to_out(db, msg)


@router.get("/chat/messages", response_model=list[ChatMessageOut])
async def get_message_history(before: uuid.UUID | None = None, limit: int = 50, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Newest-first page of up to `limit` messages, then returned oldest-
    first for the client to prepend. `before` (a message id, not a
    timestamp -- clients never need to know server clock format) pages
    further back in history for infinite-scroll; it used to be accepted
    but silently ignored, so every "page" was just the newest 50 messages
    again. See DECISIONS.md."""
    query = select(ChatMessage).order_by(ChatMessage.created_at.desc())
    if before is not None:
        anchor_result = await db.execute(select(ChatMessage.created_at).where(ChatMessage.id == before))
        anchor_created_at = anchor_result.scalar_one_or_none()
        if anchor_created_at is not None:
            query = query.where(ChatMessage.created_at < anchor_created_at)
    query = query.limit(limit)
    result = await db.execute(query)
    messages = list(reversed(result.scalars().all()))
    return [await _msg_to_out(db, m) for m in messages]


@router.get("/chat/media", response_model=list[ChatMediaOut])
async def list_chat_media(spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Every photo/video ever exchanged in chat, newest first -- powers the
    gallery screen. See DECISIONS.md."""
    result = await db.execute(
        select(ChatMessage, MediaAsset)
        .join(MediaAsset, MediaAsset.chat_message_id == ChatMessage.id)
        .where(ChatMessage.content_type.in_([ChatContentTypeEnum.photo, ChatContentTypeEnum.video]))
        .order_by(ChatMessage.created_at.desc())
    )
    rows = result.all()
    return [
        ChatMediaOut(
            message_id=msg.id, media_asset_id=asset.id, content_type=msg.content_type.value,
            has_thumbnail=asset.thumbnail_object_key is not None, created_at=msg.created_at,
        )
        for msg, asset in rows
    ]


@router.post("/chat/messages/{message_id}/read")
async def mark_read(message_id: uuid.UUID, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(ChatMessage).where(ChatMessage.id == message_id))
    msg = result.scalar_one_or_none()
    if msg is None:
        raise HTTPException(status_code=404, detail="Not found")
    if msg.sender_id != spouse.id and msg.read_at is None:
        msg.read_at = utcnow()
        await db.commit()
        # Tell the sender's live connection so their "seen" tick updates
        # immediately instead of only on their next full reload.
        await ws_manager.send_to_spouse(str(msg.sender_id), {
            "type": "chat_read", "message_id": str(msg.id), "read_at": msg.read_at.isoformat(),
        })
    return {"ok": True}


@router.websocket("/ws/chat")
async def chat_ws(websocket: WebSocket, token: str = Query(...)):
    try:
        claims = decode_token_safe(token)
    except TokenError:
        await websocket.close(code=4401)
        return
    if claims.get("type") != "access":
        await websocket.close(code=4401)
        return

    spouse_id = claims["sub"]
    role = claims.get("role")

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Spouse).where(Spouse.id == uuid.UUID(spouse_id)))
        spouse = result.scalar_one_or_none()
        if spouse is None:
            await websocket.close(code=4401)
            return

    await ws_manager.connect(spouse_id, websocket)
    try:
        while True:
            raw = await websocket.receive_text()
            try:
                data = json.loads(raw)
                msg_type = data.get("type")
                if msg_type == "ping":
                    await websocket.send_text(json.dumps({"type": "pong"}))
                    continue
                if msg_type == "chat_message":
                    payload = ChatMessageCreate(**data.get("payload", {}))
                    async with AsyncSessionLocal() as db:
                        sender_result = await db.execute(select(Spouse).where(Spouse.id == uuid.UUID(spouse_id)))
                        sender = sender_result.scalar_one()
                        msg = await _persist_message(db, sender, payload)

                        target_role = other_role(role)
                        target_result = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(target_role)))
                        target = target_result.scalar_one_or_none()
                        out = await _msg_to_out(db, msg)

                        if target is not None:
                            delivered = await ws_manager.send_to_spouse(str(target.id), {"type": "chat_message", "message": json.loads(out.model_dump_json())})
                            if delivered:
                                msg.delivered_at = utcnow()
                                await db.commit()
                            tokens_result = await db.execute(select(Device.push_token).where(Device.spouse_id == target.id, Device.push_token.is_not(None)))
                            tokens = [t for t in tokens_result.scalars().all() if t]
                            await notify_spouse(db, str(target.id), tokens, category="chat", content_type=payload.content_type)

                        await websocket.send_text(json.dumps({"type": "chat_ack", "message": json.loads((await _msg_to_out(db, msg)).model_dump_json())}))
                if msg_type == "typing":
                    # `kind` distinguishes "typing a text message" from
                    # "recording a voice message" -- both are shown as a
                    # live indicator on the other spouse's screen. Defaults
                    # to "text" so older clients that don't send it yet
                    # still work. See DECISIONS.md.
                    kind = data.get("kind", "text")
                    async with AsyncSessionLocal() as db:
                        target_role = other_role(role)
                        target_result = await db.execute(select(Spouse.id).where(Spouse.role == RoleEnum(target_role)))
                        target_id = target_result.scalar_one_or_none()
                        if target_id:
                            await ws_manager.send_to_spouse(str(target_id), {"type": "typing", "kind": kind})
            except Exception:
                await websocket.send_text(json.dumps({"type": "error", "detail": "malformed message"}))
    except WebSocketDisconnect:
        ws_manager.disconnect(spouse_id, websocket)
