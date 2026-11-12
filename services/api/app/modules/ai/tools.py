"""Read-only tools exposed to the model (AI_ARCHITECTURE.md §5).

There are no write or exec tools. Every tool runs org-scoped queries and its result is
registered as new evidence, so answers cite it like any other evidence.
"""

import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, cast, get_args
from uuid import UUID

from sqlalchemy import case, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.ai import collector
from app.modules.ai.evidence import EvidenceRegistry, Redactor
from app.modules.ai.providers.base import ToolCall, ToolResult, ToolSpec
from app.modules.incidents.models import Incident
from app.modules.services.models import Service
from app.modules.telemetry.metrics import ERROR_RATE, Agg

MAX_RANGE = timedelta(days=7)
MAX_CALLS_PER_TURN = 6
MAX_CALLS_PER_INVESTIGATION = 20
MAX_LOG_LIMIT = 50
MAX_SIMILAR_LIMIT = 5

_RANGE = {
    "from": {"type": "string", "description": "ISO 8601 start time (UTC)"},
    "to": {"type": "string", "description": "ISO 8601 end time (UTC)"},
}


def _tool(name: str, description: str, props: dict[str, Any]) -> ToolSpec:
    return ToolSpec(
        name=name,
        description=description,
        input_schema={
            "type": "object",
            "additionalProperties": False,
            "required": list(props),
            "properties": props,
        },
    )


TOOLS: list[ToolSpec] = [
    _tool(
        "query_metric",
        "Summarise one metric of a service over a time range (mean, peak, per-minute "
        "series). Use metric 'http.server.error_rate' with aggregation 'ratio' for errors.",
        {
            "service": {"type": "string", "description": "service slug"},
            "metric": {"type": "string"},
            "aggregation": {"type": "string", "enum": list(get_args(Agg))},
            **_RANGE,
        },
    ),
    _tool(
        "search_logs",
        "Find log messages of a service grouped by fingerprint, most frequent first.",
        {
            "service": {"type": "string", "description": "service slug"},
            "level": {"type": "string", "enum": ["any", "info", "warn", "error", "fatal"]},
            "contains": {
                "type": ["string", "null"],
                "description": "case-insensitive substring, or null",
            },
            **_RANGE,
            "limit": {"type": "integer", "description": f"max groups, 1-{MAX_LOG_LIMIT}"},
        },
    ),
    _tool(
        "list_deployments",
        "List deployments of a service that started in a time range.",
        {"service": {"type": "string", "description": "service slug"}, **_RANGE},
    ),
    _tool(
        "get_incident",
        "Fetch another incident of this organization by key, e.g. INC-1001.",
        {"key": {"type": "string"}},
    ),
    _tool(
        "find_similar_incidents",
        "Recent past incidents of a service (resolved first), with any human-confirmed "
        "root cause and resolution notes.",
        {
            "service": {"type": "string", "description": "service slug"},
            "limit": {"type": "integer", "description": f"1-{MAX_SIMILAR_LIMIT}"},
        },
    ),
]


class ToolInputError(Exception):
    pass


def _ts(value: Any, field: str) -> datetime:
    if not isinstance(value, str):
        raise ToolInputError(f"'{field}' must be an ISO 8601 string")
    try:
        t = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as e:
        raise ToolInputError(f"'{field}' is not a valid ISO 8601 time") from e
    return t if t.tzinfo else t.replace(tzinfo=UTC)


@dataclass
class ToolExecutor:
    session: AsyncSession
    org_id: UUID
    registry: EvidenceRegistry
    redact: Redactor
    now: datetime

    def _range(self, args: dict[str, Any]) -> tuple[datetime, datetime, list[str]]:
        notes: list[str] = []
        start, end = _ts(args.get("from"), "from"), _ts(args.get("to"), "to")
        if end > self.now:
            end = self.now
        if start >= end:
            raise ToolInputError("'from' must be before 'to'")
        if end - start > MAX_RANGE:
            start = end - MAX_RANGE
            notes.append("Range clamped to the last 7 days of the requested window.")
        return start, end, notes

    async def _service(self, slug: Any) -> Service:
        if not isinstance(slug, str) or not slug:
            raise ToolInputError("'service' must be a service slug")
        svc = await self.session.scalar(
            select(Service)
            .where(
                Service.org_id == self.org_id,
                Service.slug == slug.lower(),
                Service.deleted_at.is_(None),
            )
            .order_by(case((Service.environment == "production", 0), else_=1))
            .limit(1)
        )
        if svc is None:
            raise ToolInputError(f"No service with slug '{slug}'")
        return svc

    async def run(self, call: ToolCall) -> ToolResult:
        before = self.registry.next_index
        try:
            notes = await self._dispatch(call.name, call.input)
        except (ToolInputError, ValueError, TypeError) as e:
            return ToolResult(call.id, json.dumps({"error": str(e)}), is_error=True)
        added = [e.for_model() for e in self.registry.items if int(e.ref[3:]) >= before]
        payload: dict[str, Any] = {"evidence": added}
        if not added:
            payload["result"] = "No matching data."
        if notes:
            payload["notes"] = notes
        return ToolResult(call.id, json.dumps(payload, default=str))

    async def _dispatch(self, name: str, args: dict[str, Any]) -> list[str]:
        reg, s, org = self.registry, self.session, self.org_id
        if name == "query_metric":
            svc = await self._service(args.get("service"))
            start, end, notes = self._range(args)
            metric, raw_agg = str(args.get("metric", "")), args.get("aggregation")
            if raw_agg not in get_args(Agg):
                raise ToolInputError(f"Unknown aggregation '{raw_agg}'")
            agg = cast(Agg, raw_agg)
            if (agg == "ratio") != (metric == ERROR_RATE):
                raise ToolInputError(f"'ratio' applies only to {ERROR_RATE}")
            await collector.add_metric_evidence(
                s, reg, org_id=org, service=svc, name=metric, agg=agg, start=start, end=end
            )
            return notes
        if name == "search_logs":
            svc = await self._service(args.get("service"))
            start, end, notes = self._range(args)
            level = args.get("level", "any")
            levels = ("debug", "info", "warn", "error", "fatal") if level == "any" else (level,)
            limit = max(1, min(int(args.get("limit") or 10), MAX_LOG_LIMIT))
            contains = args.get("contains")
            await collector.add_log_evidence(
                s,
                reg,
                self.redact,
                org_id=org,
                service=svc,
                start=start,
                end=end,
                levels=tuple(str(lv) for lv in levels),
                contains=str(contains)[:100] if contains else None,
                limit=limit,
            )
            return notes
        if name == "list_deployments":
            svc = await self._service(args.get("service"))
            start, end, notes = self._range(args)
            await collector.add_deployment_evidence(
                s, reg, self.redact, org_id=org, service=svc, start=start, end=end, limit=20
            )
            return notes
        if name == "get_incident":
            key = str(args.get("key", "")).upper().removeprefix("INC-")
            if not key.isdigit():
                raise ToolInputError("'key' must look like INC-1001")
            inc = await s.scalar(
                select(Incident).where(Incident.org_id == org, Incident.number == int(key))
            )
            if inc is None:
                raise ToolInputError(f"No incident INC-{key}")
            svc_slug = (
                await s.scalar(
                    select(Service.slug).where(Service.org_id == org, Service.id == inc.service_id)
                )
                if inc.service_id
                else None
            )
            collector.add_incident_evidence(reg, self.redact, inc, service_slug=svc_slug)
            return []
        if name == "find_similar_incidents":
            svc = await self._service(args.get("service"))
            limit = max(1, min(int(args.get("limit") or 3), MAX_SIMILAR_LIMIT))
            await collector.add_similar_incidents(
                s,
                reg,
                self.redact,
                org_id=org,
                service=svc,
                exclude=None,
                before=self.now,
                limit=limit,
            )
            return []
        raise ToolInputError(f"Unknown tool '{name}'")
