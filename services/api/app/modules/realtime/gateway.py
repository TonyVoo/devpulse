"""WebSocket gateway (ARCHITECTURE.md §8, ADR-009).

1. `POST /api/v1/realtime/ticket {org_id}` (bearer auth, membership checked) → single-use
   ticket valid for 30 s, so long-lived JWTs never appear in URLs or proxy logs.
2. `GET /ws?ticket=…` upgrades, consumes the ticket and streams the org's Redis channel.

Messages are hints (`{"type":"sync","collection":"incidents","change_seq":N}`); clients
react with a delta sync, so a dropped connection never loses or duplicates data.
Close codes: 4401 invalid/expired ticket · 4403 membership revoked.
"""

import asyncio
import contextlib
import json
import secrets
from datetime import UTC, datetime
from typing import Annotated, Any
from uuid import UUID

import structlog
from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from sqlalchemy import select

from app.core.db import get_sessionmaker
from app.core.deps import CurrentUserDep, SessionDep
from app.core.redis import get_redis
from app.core.tenancy import load_org_context
from app.modules.organizations.models import Membership, Organization

log = structlog.get_logger(__name__)

TICKET_TTL_S = 30
PING_EVERY_S = 25
MEMBERSHIP_RECHECK_S = 60


def channel(org_id: UUID | str) -> str:
    return f"org:{org_id}"


class TicketIn(BaseModel):
    org_id: UUID


class TicketOut(BaseModel):
    ticket: str
    expires_in: int
    path: str = "/ws"


router = APIRouter(tags=["realtime"])


@router.post("/api/v1/realtime/ticket", response_model=TicketOut)
async def create_ticket(body: TicketIn, current: CurrentUserDep, session: SessionDep) -> TicketOut:
    await load_org_context(session, body.org_id, current.id)  # 404 if not a member
    ticket = secrets.token_urlsafe(32)
    await get_redis().set(
        f"ws:ticket:{ticket}",
        json.dumps({"user_id": str(current.id), "org_id": str(body.org_id)}),
        ex=TICKET_TTL_S,
    )
    return TicketOut(ticket=ticket, expires_in=TICKET_TTL_S)


async def _still_member(user_id: str, org_id: str) -> bool:
    async with get_sessionmaker()() as session:
        row = await session.scalar(
            select(Membership.id)
            .join(Organization, Organization.id == Membership.org_id)
            .where(
                Membership.user_id == UUID(user_id),
                Membership.org_id == UUID(org_id),
                Organization.deleted_at.is_(None),
            )
        )
        return row is not None


@router.websocket("/ws")
async def websocket(ws: WebSocket, ticket: Annotated[str, Query(max_length=80)] = "") -> None:
    raw = await get_redis().getdel(f"ws:ticket:{ticket}") if ticket else None
    await ws.accept()
    if raw is None:
        await ws.close(code=4401, reason="invalid or expired ticket")
        return
    claims: dict[str, Any] = json.loads(raw)
    user_id, org_id = claims["user_id"], claims["org_id"]
    bound = log.bind(user_id=user_id, org_id=org_id)

    pubsub = get_redis().pubsub()
    await pubsub.subscribe(channel(org_id))
    await ws.send_json(
        {"type": "hello", "org_id": org_id, "server_time": datetime.now(UTC).isoformat()}
    )
    bound.info("ws_connected")

    async def forward() -> None:
        async for message in pubsub.listen():
            if message.get("type") == "message":
                await ws.send_text(message["data"])

    async def heartbeat() -> None:
        since_check = 0
        while True:
            await asyncio.sleep(PING_EVERY_S)
            await ws.send_json({"type": "ping"})
            since_check += PING_EVERY_S
            if since_check >= MEMBERSHIP_RECHECK_S:
                since_check = 0
                if not await _still_member(user_id, org_id):
                    await ws.close(code=4403, reason="membership revoked")
                    return

    async def receive() -> None:
        while True:
            await ws.receive_text()  # pongs / client pings; content is ignored

    tasks = [asyncio.create_task(t()) for t in (forward, heartbeat, receive)]
    try:
        _, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for t in pending:
            t.cancel()
    except WebSocketDisconnect:
        pass
    finally:
        for t in tasks:
            t.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await t
        with contextlib.suppress(Exception):
            await pubsub.unsubscribe(channel(org_id))
            await pubsub.aclose()  # type: ignore[no-untyped-call]
        bound.info("ws_disconnected")
