"""Response hardening and request size limits (Phase 6 security review, docs/SECURITY.md).

Pure ASGI (no BaseHTTPMiddleware) so streaming responses and WebSockets pass through
untouched and the body limit applies while the body is being read, not after.
"""

import json
from collections.abc import Awaitable, Callable, MutableMapping
from typing import Any

Scope = MutableMapping[str, Any]
Message = MutableMapping[str, Any]
Receive = Callable[[], Awaitable[Message]]
Send = Callable[[Message], Awaitable[None]]
ASGIApp = Callable[[Scope, Receive, Send], Awaitable[None]]

_BASE_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    (b"x-frame-options", b"DENY"),
    (b"referrer-policy", b"no-referrer"),
    (b"cross-origin-resource-policy", b"same-site"),
]
# JSON API: nothing may be rendered, framed or scripted from these responses.
_API_CSP = (b"content-security-policy", b"default-src 'none'; frame-ancestors 'none'")
_HSTS = (b"strict-transport-security", b"max-age=31536000; includeSubDomains")


class SecurityMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        *,
        max_body_bytes: int,
        max_ingest_body_bytes: int,
        hsts: bool,
    ) -> None:
        self.app = app
        self.max_body = max_body_bytes
        self.max_ingest_body = max_ingest_body_bytes
        self.hsts = hsts

    def _limit_for(self, path: str) -> int:
        return self.max_ingest_body if path.startswith("/ingest/") else self.max_body

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        path: str = scope.get("path", "")
        limit = self._limit_for(path)

        declared = next(
            (int(v) for k, v in scope.get("headers", []) if k == b"content-length" and v.isdigit()),
            None,
        )
        if declared is not None and declared > limit:
            await _too_large(send, limit)
            return

        received = 0
        rejected = False

        async def limited_receive() -> Message:
            # Chunked bodies without Content-Length are counted as they arrive. Frameworks turn
            # exceptions raised here into 400s, so answer 413 ourselves and tell the app the
            # client went away; whatever it sends afterwards is dropped.
            nonlocal received, rejected
            if rejected:
                return {"type": "http.disconnect"}
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    rejected = True
                    await _too_large(send, limit)
                    return {"type": "http.disconnect"}
            return message

        is_docs = path.startswith(("/docs", "/openapi.json"))

        async def secure_send(message: Message) -> None:
            if rejected:
                return
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                present = {k.lower() for k, _ in headers}
                extra = [h for h in _BASE_HEADERS if h[0] not in present]
                if not is_docs and _API_CSP[0] not in present:
                    extra.append(_API_CSP)
                if self.hsts:
                    extra.append(_HSTS)
                # Authenticated JSON must never be cached by browsers or proxies.
                if path.startswith("/api/") and b"cache-control" not in present:
                    extra.append((b"cache-control", b"no-store"))
                message["headers"] = headers + extra
            await send(message)

        try:
            await self.app(scope, limited_receive, secure_send)
        except Exception:
            if not rejected:
                raise


async def _too_large(send: Send, limit: int) -> None:
    body = json.dumps(
        {
            "type": "https://docs.devpulse.dev/errors/request.too_large",
            "title": "Request too large",
            "status": 413,
            "detail": f"The request body exceeds {limit} bytes.",
            "code": "request.too_large",
        }
    ).encode()
    await send(
        {
            "type": "http.response.start",
            "status": 413,
            "headers": [
                (b"content-type", b"application/problem+json"),
                (b"content-length", str(len(body)).encode()),
                *_BASE_HEADERS,
            ],
        }
    )
    await send({"type": "http.response.body", "body": body})
