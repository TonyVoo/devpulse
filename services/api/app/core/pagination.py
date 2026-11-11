"""Opaque keyset cursors: base64(json([iso_timestamp, uuid]))."""

import base64
import binascii
import json
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

from app.core.errors import Unprocessable

MAX_LIMIT = 200


class Page[T](BaseModel):
    items: list[T]
    next_cursor: str | None


def encode_cursor(ts: datetime, id_: UUID) -> str:
    raw = json.dumps([ts.isoformat(), str(id_)]).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        ts, id_ = json.loads(base64.urlsafe_b64decode(padded))
        return datetime.fromisoformat(ts), UUID(id_)
    except (ValueError, TypeError, binascii.Error, json.JSONDecodeError) as e:
        raise Unprocessable("Invalid cursor", code="pagination.invalid_cursor") from e


def encode_text_cursor(key: str, id_: UUID) -> str:
    """Keyset cursor for lists ordered by a text column (e.g. name) then id."""
    raw = json.dumps(["t", key, str(id_)]).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def decode_text_cursor(cursor: str) -> tuple[str, UUID]:
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        tag, key, id_ = json.loads(base64.urlsafe_b64decode(padded))
        if tag != "t" or not isinstance(key, str):
            raise ValueError("not a text cursor")
        return key, UUID(id_)
    except (ValueError, TypeError, binascii.Error, json.JSONDecodeError) as e:
        raise Unprocessable("Invalid cursor", code="pagination.invalid_cursor") from e
