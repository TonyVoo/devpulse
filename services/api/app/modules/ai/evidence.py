"""Evidence registry and redaction (AI_ARCHITECTURE.md §2).

Evidence only ever comes from DevPulse's own stores. Each item gets a stable ref (EV-n), a
compact excerpt computed here in Python, and the exact query used to fetch it.
"""

import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from app.modules.ai.models import EvidenceKind

_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
_IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
# Bearer tokens, API keys, JWTs, long hex/base64 blobs.
_SECRET = re.compile(
    r"(?i)\b(?:bearer\s+)[A-Za-z0-9._~+/=-]{8,}"
    r"|\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"
    r"|\b(?:sk|pk|rk|dp|ghp|gho|xox[abp])[-_][A-Za-z0-9_-]{12,}"
    r"|(?i:(?:password|passwd|secret|token|api[_-]?key)\s*[=:]\s*)\S+"
    r"|\b[A-Fa-f0-9]{40,}\b"
)


@dataclass(frozen=True)
class Redactor:
    emails: bool = True
    ips: bool = True
    secrets: bool = True

    @classmethod
    def from_settings(cls, cfg: dict[str, Any] | None) -> "Redactor":
        cfg = cfg or {}
        return cls(
            emails=bool(cfg.get("emails", True)),
            ips=bool(cfg.get("ips", True)),
            secrets=bool(cfg.get("secrets", True)),
        )

    def __call__(self, text: str | None, *, limit: int = 300) -> str | None:
        if text is None:
            return None
        if self.secrets:
            text = _SECRET.sub("[redacted-secret]", text)
        if self.emails:
            text = _EMAIL.sub("[redacted-email]", text)
        if self.ips:
            text = _IPV4.sub("[redacted-ip]", text)
        return text if len(text) <= limit else text[: limit - 1] + "…"


@dataclass
class Evidence:
    ref: str
    kind: EvidenceKind
    title: str
    excerpt: dict[str, Any]  # always includes "text": a one-line human summary
    source_query: dict[str, Any]
    observed_at: datetime | None = None

    def for_model(self) -> dict[str, Any]:
        return {"ref": self.ref, "kind": self.kind.value, "title": self.title, **self.excerpt}


@dataclass
class EvidenceRegistry:
    items: list[Evidence] = field(default_factory=list)
    next_index: int = 1

    def add(
        self,
        kind: EvidenceKind,
        title: str,
        excerpt: dict[str, Any],
        source_query: dict[str, Any],
        observed_at: datetime | None = None,
    ) -> Evidence:
        ev = Evidence(
            ref=f"EV-{self.next_index}",
            kind=kind,
            title=title[:200],
            excerpt=excerpt,
            source_query=source_query,
            observed_at=observed_at,
        )
        self.next_index += 1
        self.items.append(ev)
        return ev

    @property
    def refs(self) -> set[str]:
        return {e.ref for e in self.items}

    def context_hash(self) -> str:
        payload = json.dumps([e.for_model() for e in self.items], sort_keys=True, default=str)
        return hashlib.sha256(payload.encode()).hexdigest()


def fmt_num(v: float | None) -> str:
    if v is None:
        return "n/a"
    if abs(v) >= 100:
        return f"{v:,.0f}"
    if abs(v) >= 1:
        return f"{v:.2f}".rstrip("0").rstrip(".")
    return f"{v:.4f}".rstrip("0").rstrip(".") or "0"


def fmt_time(t: datetime | None) -> str:
    return t.strftime("%H:%M UTC") if t else "n/a"
