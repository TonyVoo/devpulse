"""Error reporting (Sentry) for every backend process. Off unless SENTRY_DSN is set.

Nothing secret or personal is sent: no default PII, credential headers and cookies are
stripped, request bodies are dropped (they may contain passwords, tokens or telemetry).
"""

from typing import Any

import sentry_sdk

from app.core.config import get_settings

_SECRET_HEADERS = {
    "authorization",
    "cookie",
    "set-cookie",
    "x-devpulse-bff-secret",
    "x-hub-signature-256",
    "idempotency-key",
}


def scrub_event(event: dict[str, Any], _hint: dict[str, Any] | None = None) -> dict[str, Any]:
    request = event.get("request")
    if isinstance(request, dict):
        headers = request.get("headers")
        if isinstance(headers, dict):
            request["headers"] = {
                k: ("[Filtered]" if k.lower() in _SECRET_HEADERS else v) for k, v in headers.items()
            }
        request.pop("data", None)  # bodies: passwords, tokens, telemetry
        request.pop("cookies", None)
        if isinstance(request.get("query_string"), str) and "key=" in request["query_string"]:
            request["query_string"] = "[Filtered]"
    event.pop("user", None)
    return event


def init_sentry(component: str) -> bool:
    """Returns True when error reporting is active."""
    s = get_settings()
    if not s.sentry_dsn:
        return False
    sentry_sdk.init(
        dsn=s.sentry_dsn,
        environment=s.app_env,
        release=s.release or None,
        server_name=component,
        send_default_pii=False,
        traces_sample_rate=s.sentry_traces_sample_rate,
        before_send=scrub_event,  # type: ignore[arg-type]
        max_request_body_size="never",
    )
    sentry_sdk.set_tag("component", component)
    return True
