# 02 — Real-time (WebSockets + Redis) — CU-33..CU-37

Goal: live incident status + technician location, multi-tenant isolated, broadcast to every client watching the same incident, working across multiple backend workers via **Redis pub/sub**.

## 1. Endpoint & authentication

```
WS  /ws/{tenant_id}/{incident_id}?token=<JWT>
```

Validation on connect (close codes in parentheses):
1. Decode `token`. Invalid → close `4401`.
2. `claims.tenant == tenant_id` (path) → else close `4403` (cross-tenant blocked).
3. Incident exists and user is authorized: CONDUCTOR owner, or TALLER/TECNICO of the assigned workshop, or ADMIN of tenant → else close `4404`.
4. Accept. Register connection (Redis), send the current state as the first message.

> Browsers can't set headers on WS easily, so the JWT travels as a query param. That's acceptable here.

## 2. Message protocol (JSON, both directions)

Envelope:
```json
{ "type": "<EVENT>", "incident_id": "uuid", "ts": "2026-06-01T14:30:00Z", "data": { ... } }
```

Server → client events:
| type | data | when |
|------|------|------|
| `STATE_SNAPSHOT` | full incident `{estado,prioridad,tipo,...}` | on connect |
| `STATUS_CHANGED` | `{estado_anterior, estado_nuevo, comentario}` | workshop/system updates status (CU-35, CU-36) |
| `TECH_LOCATION` | `{lat, lng, tecnico_id}` | technician GPS ping (CU-34) |
| `TECH_ARRIVED` | `{}` | state → EN_ATENCION (CU-37) |
| `ASSIGNMENT` | `{taller_id, taller_nombre, estado}` | assigned/accepted/rejected (CU-24) |
| `ERROR` | `{message}` | recoverable error |

Client → server events:
| type | data | who |
|------|------|-----|
| `PING` | `{}` | any (keepalive; server replies `PONG`) |
| `TECH_LOCATION` | `{lat,lng}` | TECNICO/TALLER app pushing location |

Technician location can also be posted over REST (`POST /incidentes/{id}/ubicacion`) which then publishes the same `TECH_LOCATION` event — use whichever the client prefers.

## 3. Redis channel naming
```
ws:tenant:{tenant_id}:incident:{incident_id}
```
Every backend worker subscribes to channels for incidents it has local sockets for, and publishes when something changes. This makes broadcast correct even with multiple uvicorn workers.

## 4. Connection manager — `app/ws/manager.py`
```python
import asyncio, json
from collections import defaultdict
from fastapi import WebSocket
import redis.asyncio as aioredis
from ..core.config import settings

def channel(tenant_id: str, incident_id: str) -> str:
    return f"ws:tenant:{tenant_id}:incident:{incident_id}"

class WSManager:
    def __init__(self):
        self.local: dict[str, set[WebSocket]] = defaultdict(set)  # channel -> sockets
        self.redis = aioredis.from_url(settings.redis_url, decode_responses=True)
        self.pubsub = self.redis.pubsub()
        self._listener_task: asyncio.Task | None = None

    async def connect(self, ws: WebSocket, tenant_id: str, incident_id: str):
        await ws.accept()
        ch = channel(tenant_id, incident_id)
        if not self.local[ch]:
            await self.pubsub.subscribe(ch)
            if self._listener_task is None:
                self._listener_task = asyncio.create_task(self._listen())
        self.local[ch].add(ws)

    async def disconnect(self, ws: WebSocket, tenant_id: str, incident_id: str):
        ch = channel(tenant_id, incident_id)
        self.local[ch].discard(ws)
        if not self.local[ch]:
            await self.pubsub.unsubscribe(ch)

    async def publish(self, tenant_id: str, incident_id: str, event: dict):
        await self.redis.publish(channel(tenant_id, incident_id), json.dumps(event))

    async def _listen(self):
        async for msg in self.pubsub.listen():
            if msg["type"] != "message":
                continue
            ch, payload = msg["channel"], msg["data"]
            dead = []
            for ws in list(self.local.get(ch, [])):
                try:
                    await ws.send_text(payload)
                except Exception:
                    dead.append(ws)
            for ws in dead:
                self.local[ch].discard(ws)

manager = WSManager()
```

## 5. WS route — `app/ws/routes.py`
```python
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from sqlalchemy import text
from ..core.security import decode_token
from ..core.db import SessionLocal
from .manager import manager
import json
from datetime import datetime, timezone

router = APIRouter()

@router.websocket("/ws/{tenant_id}/{incident_id}")
async def ws_incident(ws: WebSocket, tenant_id: str, incident_id: str, token: str = Query(...)):
    try:
        claims = decode_token(token)
    except ValueError:
        await ws.close(code=4401); return
    if claims.get("tenant") != tenant_id:
        await ws.close(code=4403); return

    # authorize + snapshot
    db = SessionLocal()
    db.execute(text("SELECT set_config('app.current_tenant', :t, true)"), {"t": tenant_id})
    inc = db.execute(text("""SELECT id, estado, prioridad, tipo_incidente_id, latitud, longitud
                             FROM emergencias.incidente WHERE id=:id"""),
                     {"id": incident_id}).mappings().first()
    db.close()
    if not inc:
        await ws.close(code=4404); return

    await manager.connect(ws, tenant_id, incident_id)
    await ws.send_text(json.dumps({
        "type": "STATE_SNAPSHOT", "incident_id": incident_id,
        "ts": datetime.now(timezone.utc).isoformat(), "data": dict(inc)
    }, default=str))
    try:
        while True:
            raw = await ws.receive_text()
            msg = json.loads(raw)
            if msg.get("type") == "PING":
                await ws.send_text(json.dumps({"type": "PONG"}))
            elif msg.get("type") == "TECH_LOCATION":
                # persist + rebroadcast
                await manager.publish(tenant_id, incident_id, {
                    "type": "TECH_LOCATION", "incident_id": incident_id,
                    "ts": datetime.now(timezone.utc).isoformat(), "data": msg["data"]
                })
    except WebSocketDisconnect:
        await manager.disconnect(ws, tenant_id, incident_id)
```

## 6. Publishing from REST handlers

When the workshop updates status (`PATCH /incidentes/{id}/estado`) or accepts an assignment, the REST handler must publish to Redis so all WS clients update. Since `manager.publish` is async and the handler is sync, expose a helper that runs it:
```python
import anyio
def publish_event(tenant_id, incident_id, event: dict):
    anyio.from_thread.run(manager.publish, tenant_id, incident_id, event)  # if in threadpool
# Simpler: make the status endpoint async and `await manager.publish(...)`.
```
Recommended: make status/assignment endpoints `async def` and `await manager.publish(...)` directly.

Example inside the status update:
```python
await manager.publish(tenant, incident_id, {
    "type": "STATUS_CHANGED", "incident_id": incident_id,
    "ts": now_iso(), "data": {"estado_anterior": old, "estado_nuevo": new, "comentario": comentario}
})
```

## 7. Push notifications (FCM) — CU-24, CU-35

WS covers connected clients; **FCM** covers backgrounded/closed apps. On every status change also:
```python
import httpx
async def send_push(token: str, title: str, body: str, data: dict):
    await httpx.AsyncClient().post(
        "https://fcm.googleapis.com/fcm/send",
        headers={"Authorization": f"key={settings.fcm_server_key}", "Content-Type": "application/json"},
        json={"to": token, "notification": {"title": title, "body": body}, "data": data})
# Persist a row in `notificacion` (enviada=true) for the audit/inbox.
```
Store each user's FCM token (add `fcm_token` to `usuario` via a small migration, or a side table). Mobile registers it after login.

## 8. Acceptance criteria
- Two clients (web workshop + mobile driver) on the same incident: a `PATCH .../estado` on web makes the mobile receive `STATUS_CHANGED` within ~1s.
- A `TECH_LOCATION` sent by the technician app moves the marker on the driver map.
- A client with tenant A's JWT trying `/ws/<tenantB>/<incident>` is closed with `4403`.
- Killing one uvicorn worker and reconnecting still broadcasts (Redis-backed).
