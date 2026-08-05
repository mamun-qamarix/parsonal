import json

from fastapi import WebSocket


class WSManager:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = {}

    async def connect(self, spouse_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections.setdefault(spouse_id, set()).add(websocket)

    def disconnect(self, spouse_id: str, websocket: WebSocket) -> None:
        conns = self._connections.get(spouse_id)
        if conns and websocket in conns:
            conns.remove(websocket)
            if not conns:
                self._connections.pop(spouse_id, None)

    async def send_to_spouse(self, spouse_id: str, payload: dict) -> bool:
        """Returns True only if the message actually reached at least one
        live connection -- previously this returned True whenever the
        connection set was merely non-empty, so a message could be marked
        `delivered_at` even though every individual send failed."""
        conns = self._connections.get(spouse_id)
        if not conns:
            return False
        dead = []
        sent = False
        message = json.dumps(payload, default=str)
        for ws in conns:
            try:
                await ws.send_text(message)
                sent = True
            except Exception:
                dead.append(ws)
        for ws in dead:
            conns.discard(ws)
        return sent

    def is_online(self, spouse_id: str) -> bool:
        return bool(self._connections.get(spouse_id))


ws_manager = WSManager()
