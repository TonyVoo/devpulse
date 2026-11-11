"""Domain errors and RFC 9457 problem+json rendering.

Services raise AppError subclasses with a stable machine-readable `code`;
clients branch on `code`, never on `detail` text.
"""

from typing import Any

import structlog
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = structlog.get_logger(__name__)

PROBLEM_JSON = "application/problem+json"


class AppError(Exception):
    status: int = 400
    code: str = "error"
    title: str = "Bad request"

    def __init__(
        self,
        detail: str | None = None,
        *,
        code: str | None = None,
        extra: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(detail or self.title)
        self.detail = detail or self.title
        if code:
            self.code = code
        self.extra = extra or {}
        self.headers = headers


class NotFound(AppError):
    status, code, title = 404, "not_found", "Not found"


class Unauthorized(AppError):
    status, code, title = 401, "auth.unauthorized", "Authentication required"


class Forbidden(AppError):
    status, code, title = 403, "rbac.forbidden", "Not allowed"


class Conflict(AppError):
    status, code, title = 409, "conflict", "Conflict"


class Unprocessable(AppError):
    status, code, title = 422, "validation.failed", "Validation failed"


class RateLimited(AppError):
    status, code, title = 429, "rate_limited", "Too many requests"


def _problem(
    request: Request,
    *,
    status: int,
    code: str,
    title: str,
    detail: str,
    extra: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    body: dict[str, Any] = {
        "type": f"https://docs.devpulse.dev/errors/{code}",
        "title": title,
        "status": status,
        "detail": detail,
        "code": code,
        "request_id": getattr(request.state, "request_id", None),
    }
    if extra:
        body.update(extra)
    return JSONResponse(body, status_code=status, media_type=PROBLEM_JSON, headers=headers)


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(request: Request, exc: AppError) -> JSONResponse:
        return _problem(
            request,
            status=exc.status,
            code=exc.code,
            title=exc.title,
            detail=exc.detail,
            extra=exc.extra,
            headers=exc.headers,
        )

    @app.exception_handler(RequestValidationError)
    async def _validation(request: Request, exc: RequestValidationError) -> JSONResponse:
        errors = [
            {"loc": list(e.get("loc", ())), "msg": e.get("msg"), "type": e.get("type")}
            for e in exc.errors()
        ]
        return _problem(
            request,
            status=422,
            code="validation.failed",
            title="Validation failed",
            detail="One or more fields are invalid",
            extra={"errors": errors},
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = {404: "not_found", 405: "method_not_allowed"}.get(exc.status_code, "http_error")
        return _problem(
            request,
            status=exc.status_code,
            code=code,
            title=str(exc.detail),
            detail=str(exc.detail),
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
        log.exception("unhandled_error", exc_info=exc)
        return _problem(
            request,
            status=500,
            code="internal",
            title="Internal server error",
            detail="An unexpected error occurred",
        )
