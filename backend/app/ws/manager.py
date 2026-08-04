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
        conns = self._connections.get(spouse_id)
        if not conns:
            return False
        dead = []
        message = json.dumps(payload, default=str)
        for ws in conns:
            try:
                await ws.send_text(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            conns.discard(ws)
        return True

    def is_online(self, spouse_id: str) -> bool:
        return bool(self._connections.get(spouse_id))


ws_manager = WSManager()
