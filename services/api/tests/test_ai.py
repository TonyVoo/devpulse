"""AI investigator: grounding/validation, pipeline, golden scenarios, guards, chat with
read-only tools, proposals, usage and the auto-trigger. No real LLM is ever called."""

import json
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import httpx
import pytest
from sqlalchemy import select

from app.core.db import get_sessionmaker
from app.core.redis import get_redis
from app.modules.ai import pipeline, providers
from app.modules.ai.evidence import EvidenceRegistry, Redactor
from app.modules.ai.models import AIUsage, EvidenceKind, RunStatus
from app.modules.ai.output import InvalidOutput, validate_analysis, validate_answer
from app.modules.ai.pipeline import run_investigation
from app.modules.ai.providers.base import (
    LLMRequest,
    LLMResult,
    ProviderError,
    ToolCall,
    Usage,
)
from app.modules.ai.providers.fake import FAKE_LABEL, FakeProvider
from app.modules.ai.scenarios import SCENARIOS, Scenario
from app.modules.ai.tools import ToolExecutor
from app.modules.ai.usage import cost_micros
from app.modules.alerts.models import Severity
from app.modules.incidents.models import Incident, IncidentSource
from app.modules.incidents.service import create_incident
from app.modules.notifications.push import RecordingPushProvider
from app.modules.services.models import Service
from app.workers.relay import relay_once
from tests.helpers import Account, add_member, create_org, problem, register

# ----------------------------------------------------------------------------- units


def _valid(refs: list[str], **over: Any) -> str:
    out = {
        "summary": "Latency rose after the deploy",
        "impact": "Checkout is slow",
        "probable_causes": [
            {
                "cause": "Bad deploy",
                "confidence": 0.9,
                "reasoning": "Timing",
                "evidence_refs": refs,
                "counter_evidence_refs": [],
                "how_to_verify": "Roll back in staging",
            }
        ],
        "recommended_actions": [
            {"action": "Look at diff", "kind": "investigate", "risk": "read_only", "rationale": ""},
            {"action": "Roll back", "kind": "remediate", "risk": "sensitive", "rationale": ""},
            {"action": "Drop table", "kind": "remediate", "risk": "destructive", "rationale": ""},
        ],
        "data_gaps": [],
        "limitations": "Correlation is not causation",
    }
    out.update(over)
    return json.dumps(out)


def test_validation_enforces_grounding_and_policy() -> None:
    known = {"EV-1", "EV-2"}
    a = validate_analysis(_valid(["EV-1", "EV-2"]), known_refs=known, incident_key="INC-1")
    cause = a.probable_causes[0]
    assert cause.status == "hypothesis" and cause.confidence_label == "high"
    assert [x.requires_approval for x in a.recommended_actions] == [False, True, True]
    assert a.incident_id == "INC-1"

    # Single evidence item → confidence capped at 0.75 (and the correction is shown).
    a = validate_analysis(_valid(["EV-1"]), known_refs=known, incident_key="INC-1")
    assert a.probable_causes[0].confidence == 0.75
    assert a.probable_causes[0].confidence_label == "high"
    assert a.adjustments

    for text, needle in [
        (_valid(["EV-9"]), "unknown evidence"),
        (_valid([]), "cites no evidence"),
        (_valid(["EV-1"], probable_causes=[]), "1 to 5"),
        ("not json", "not valid JSON"),
        (None, "empty"),
        (json.dumps({"summary": "x"}), "probable_causes"),
    ]:
        with pytest.raises(InvalidOutput) as e:
            validate_analysis(text, known_refs=known, incident_key="INC-1")
        assert needle in str(e.value), (needle, str(e.value))


def test_confidence_labels_and_answers() -> None:
    raw = json.loads(_valid(["EV-1", "EV-2"]))
    raw["probable_causes"][0]["confidence"] = 0.39
    a = validate_analysis(json.dumps(raw), known_refs={"EV-1", "EV-2"}, incident_key="INC-1")
    assert a.probable_causes[0].confidence_label == "low"
    raw["probable_causes"][0]["confidence"] = 1.4
    with pytest.raises(InvalidOutput):
        validate_analysis(json.dumps(raw), known_refs={"EV-1", "EV-2"}, incident_key="INC-1")

    ok = validate_answer('{"answer": "see EV-1", "evidence_refs": ["EV-1"]}', known_refs={"EV-1"})
    assert ok.evidence_refs == ["EV-1"]
    with pytest.raises(InvalidOutput):
        validate_answer('{"answer": "x", "evidence_refs": ["EV-7"]}', known_refs={"EV-1"})


def test_redaction() -> None:
    r = Redactor()
    text = (
        "user ada@example.com from 10.1.2.3 sent Authorization: Bearer abcdefghijklmnop "
        "password=hunter2 key sk-live_abcdefghijklmnop"
    )
    out = r(text, limit=1000) or ""
    for secret in ("ada@example.com", "10.1.2.3", "abcdefghijklmnop", "hunter2"):
        assert secret not in out
    assert Redactor(emails=False)("ada@example.com") == "ada@example.com"
    assert len(r("x" * 500, limit=50) or "") == 50


def test_cost_uses_the_pricing_table() -> None:
    usage = Usage(input_tokens=1000, output_tokens=500, cached_tokens=2000, cache_write_tokens=100)
    # $4 / $20 / $0.20 / $5 per MTok == micro-dollars per token.
    assert cost_micros("claude-opus-5-5", usage) == 4000 + 10000 + 400 + 500
    assert cost_micros("unknown-model", usage) == 0


# ------------------------------------------------------------------------ harness


@pytest.fixture
def queued(monkeypatch: pytest.MonkeyPatch) -> list[UUID]:
    ids: list[UUID] = []
    monkeypatch.setattr(pipeline, "enqueue", ids.append)
    return ids


@pytest.fixture
def use_provider(monkeypatch: pytest.MonkeyPatch) -> Callable[[FakeProvider], FakeProvider]:
    def install(p: FakeProvider) -> FakeProvider:
        monkeypatch.setattr(providers, "provider_factory", lambda name: p)
        return p

    install(FakeProvider())  # rule-based by default
    return install


async def _ai_org(client: httpx.AsyncClient, **settings: Any) -> tuple[Account, str]:
    owner = await register(client, f"ai-{uuid4().hex[:8]}@example.com", "Ada")
    org = await create_org(client, owner, "AI Org")
    body = {
        "enabled": True,
        "provider": "fake",
        "model": None,
        "monthly_budget_micros": 5_000_000,
        "max_tokens_per_run": 200_000,
        "auto_investigate_min_severity": None,
        **settings,
    }
    r = await client.put(f"/orgs/{org}/ai/settings", json=body, headers=owner.h)
    assert r.status_code == 200, r.text
    return owner, org


async def _scenario(org_id: str, scenario: Scenario) -> Incident:
    async with get_sessionmaker()() as s:
        inc = await scenario.build(s, UUID(org_id), datetime.now(UTC) - timedelta(minutes=10))
        await s.commit()
        return inc


async def _run_all(ids: list[UUID]) -> None:
    while ids:
        async with get_sessionmaker()() as s:
            await run_investigation(s, ids.pop(0))


async def _investigate(
    client: httpx.AsyncClient, owner: Account, org: str, ref: str, queued: list[UUID]
) -> dict[str, Any]:
    r = await client.post(f"/orgs/{org}/incidents/{ref}/investigations", headers=owner.h)
    assert r.status_code == 202, r.text
    assert r.json()["status"] == "queued"
    await _run_all(queued)
    r = await client.get(f"/orgs/{org}/ai/investigations/{r.json()['id']}", headers=owner.h)
    assert r.status_code == 200
    return dict(r.json())


# ----------------------------------------------------------------- golden scenarios


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: s.name)
async def test_golden_scenarios(
    client: httpx.AsyncClient,
    queued: list[UUID],
    use_provider: Callable[[FakeProvider], FakeProvider],
    scenario: Scenario,
) -> None:
    owner, org = await _ai_org(client)
    inc = await _scenario(org, scenario)
    inv = await _investigate(client, owner, org, inc.key, queued)

    assert inv["status"] == "succeeded", inv
    assert inv["provider"] == "fake" and inv["is_demo_provider"] is True
    result = inv["result"]
    top = result["probable_causes"][0]["cause"].lower()
    assert any(k in top for k in scenario.expected_keywords), (scenario.name, top)
    assert result["limitations"] == FAKE_LABEL
    # Grounding: every citation points at stored evidence with a reproducible query.
    refs = {e["ref"] for e in inv["evidence"]}
    for c in result["probable_causes"]:
        assert c["status"] == "hypothesis"
        assert set(c["evidence_refs"]) <= refs and c["evidence_refs"]
    assert all(e["source_query"]["type"] for e in inv["evidence"])
    # Collector data gaps are always surfaced.
    assert any("dependencies are not modelled" in g for g in result["data_gaps"])
    # Sensitive actions become proposals; none executes on its own.
    sensitive = [a for a in result["recommended_actions"] if a["risk"] != "read_only"]
    assert len(inv["proposals"]) == len(sensitive)
    assert all(a["requires_approval"] and a["proposal_id"] for a in sensitive)
    assert all(p["executes_automatically"] is False for p in inv["proposals"])

    timeline = await client.get(f"/orgs/{org}/incidents/{inc.key}/timeline", headers=owner.h)
    ai_events = [e for e in timeline.json()["items"] if e["type"] == "ai_analysis"]
    assert ai_events and ai_events[-1]["actor_type"] == "ai"
    assert ai_events[-1]["data"]["status"] == "succeeded"


async def test_bad_deploy_evidence_is_computed_not_generated(
    client: httpx.AsyncClient, queued: list[UUID], use_provider: Any
) -> None:
    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[0])
    inv = await _investigate(client, owner, org, inc.key, queued)
    by_kind: dict[str, list[dict[str, Any]]] = {}
    for e in inv["evidence"]:
        by_kind.setdefault(e["kind"], []).append(e)
    deploy = by_kind["deployment"][0]["excerpt"]
    assert deploy["version"] == "v2.14.0" and deploy["minutes_before_incident"] == 12
    latency = next(
        e["excerpt"]
        for e in by_kind["metric"]
        if e["excerpt"]["metric"] == "http.server.duration_ms"
    )
    assert 170 < latency["baseline"] < 190 and latency["peak"] > 1300
    assert latency["first_above_1_5x_baseline_at"] is not None
    log = by_kind["log"][0]["excerpt"]
    assert log["seen_in_previous_6h"] == 0 and "CartSerializer" in log["sample_message"]
    # Rule-based mode ran entirely on the structured context; the rendered prompt carried
    # the same evidence inside an untrusted <data> block.
    usage = await _usage_rows(inv["id"])
    assert [u.outcome for u in usage] == ["ok"] and usage[0].model == "fake-rules-v1"


async def _usage_rows(inv_id: str) -> list[AIUsage]:
    async with get_sessionmaker()() as s:
        return list(
            (
                await s.scalars(
                    select(AIUsage)
                    .where(AIUsage.investigation_id == UUID(inv_id))
                    .order_by(AIUsage.created_at)
                )
            ).all()
        )


# --------------------------------------------------------------------------- guards


async def test_ai_is_off_until_an_admin_enables_it(
    client: httpx.AsyncClient, queued: list[UUID], use_provider: Any
) -> None:
    owner = await register(client, "off@example.com")
    org = await create_org(client, owner)
    settings = await client.get(f"/orgs/{org}/ai/settings", headers=owner.h)
    assert settings.json()["enabled"] is False
    assert "api_key" not in json.dumps(settings.json()).lower()
    inc = await client.post(
        f"/orgs/{org}/incidents",
        json={"title": "Checkout down", "severity": "sev2"},
        headers=owner.h,
    )
    r = await client.post(
        f"/orgs/{org}/incidents/{inc.json()['key']}/investigations", headers=owner.h
    )
    assert r.status_code == 409 and problem(r)["code"] == "ai.disabled"
    assert queued == []


async def test_unconfigured_provider_cannot_be_enabled(client: httpx.AsyncClient) -> None:
    owner = await register(client, "anth@example.com")
    org = await create_org(client, owner)
    r = await client.put(
        f"/orgs/{org}/ai/settings",
        json={
            "enabled": True,
            "provider": "anthropic",
            "monthly_budget_micros": 1,
            "max_tokens_per_run": 10_000,
        },
        headers=owner.h,
    )
    assert r.status_code == 422 and problem(r)["code"] == "ai.provider_unconfigured"
    providers_ = (await client.get(f"/orgs/{org}/ai/settings", headers=owner.h)).json()
    assert {p["name"]: p["configured"] for p in providers_["providers"]} == {
        "gemini": False,
        "anthropic": False,
        "fake": True,
    }


async def test_settings_require_ai_configure(client: httpx.AsyncClient) -> None:
    owner, org = await _ai_org(client)
    eng = await register(client, "eng-ai@example.com")
    await add_member(client, org, owner, eng, "engineer")
    r = await client.put(
        f"/orgs/{org}/ai/settings",
        json={"enabled": False, "monthly_budget_micros": 0, "max_tokens_per_run": 10_000},
        headers=eng.h,
    )
    assert r.status_code == 403


async def test_one_active_run_per_incident(
    client: httpx.AsyncClient, queued: list[UUID], use_provider: Any
) -> None:
    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[0])
    url = f"/orgs/{org}/incidents/{inc.key}/investigations"
    first = await client.post(url, headers=owner.h)
    second = await client.post(url, headers=owner.h)
    assert first.status_code == 202
    assert second.status_code == 409 and problem(second)["code"] == "ai.already_running"
    assert problem(second)["investigation_id"] == first.json()["id"]
    await _run_all(queued)
    assert (await client.post(url, headers=owner.h)).status_code == 202  # finished → allowed


async def test_budget_is_enforced_before_and_at_run_time(
    client: httpx.AsyncClient, queued: list[UUID], use_provider: Any
) -> None:
    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[1])
    url = f"/orgs/{org}/incidents/{inc.key}/investigations"
    r = await client.post(url, headers=owner.h)
    assert r.status_code == 202
    # Budget drops to zero while the run is queued → rejected when the worker picks it up.
    await client.put(
        f"/orgs/{org}/ai/settings",
        json={
            "enabled": True,
            "provider": "fake",
            "monthly_budget_micros": 0,
            "max_tokens_per_run": 10_000,
        },
        headers=owner.h,
    )
    await _run_all(queued)
    inv = await client.get(f"/orgs/{org}/ai/investigations/{r.json()['id']}", headers=owner.h)
    assert inv.json()["status"] == "rejected"
    assert inv.json()["error_code"] == "ai.budget_exceeded"
    again = await client.post(url, headers=owner.h)
    assert again.status_code == 409 and problem(again)["code"] == "ai.budget_exceeded"


async def test_no_telemetry_means_no_llm_call(
    client: httpx.AsyncClient,
    queued: list[UUID],
    use_provider: Callable[[FakeProvider], FakeProvider],
) -> None:
    fake = use_provider(FakeProvider(script=[]))
    owner, org = await _ai_org(client)
    inc = await client.post(
        f"/orgs/{org}/incidents", json={"title": "Mystery", "severity": "sev2"}, headers=owner.h
    )
    inv = await _investigate(client, owner, org, inc.json()["key"], queued)
    assert inv["status"] == "failed" and inv["error_code"] == "ai.no_evidence"
    assert "not linked to a service" in inv["error_detail"]
    assert fake.requests == []  # nothing invented, nothing sent


# --------------------------------------------------------- repair / provider failures


def _scripted_valid(req: LLMRequest) -> LLMResult:
    refs = [e["ref"] for e in (req.context or {})["evidence"]][:2]
    return LLMResult(
        text=_valid(refs),
        tool_calls=[],
        usage=Usage(input_tokens=1000, output_tokens=200),
        model="claude-opus-5-5",
    )


async def test_invalid_output_gets_one_repair(
    client: httpx.AsyncClient,
    queued: list[UUID],
    use_provider: Callable[[FakeProvider], FakeProvider],
) -> None:
    bad = LLMResult(
        text=_valid(["EV-99"]), tool_calls=[], usage=Usage(500, 100), model="claude-opus-5-5"
    )
    fake = use_provider(FakeProvider(script=[bad, _scripted_valid]))
    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[0])
    inv = await _investigate(client, owner, org, inc.key, queued)
    assert inv["status"] == "succeeded"
    repair = fake.requests[1]
    assert repair.purpose == "repair" and "EV-99" in (repair.messages[-1].text or "")
    usage = await _usage_rows(inv["id"])
    assert [u.outcome for u in usage] == ["invalid_output", "ok"]
    assert [u.purpose for u in usage] == ["investigate", "repair"]
    assert usage[1].cost_micros == 1000 * 4 + 200 * 20
    assert inv["tokens_used"] == 600 + 1200


async def test_invalid_twice_fails_without_touching_the_incident(
    client: httpx.AsyncClient,
    queued: list[UUID],
    use_provider: Callable[[FakeProvider], FakeProvider],
) -> None:
    bad = LLMResult(text="{}", tool_calls=[], usage=Usage(10, 10), model="claude-opus-5-5")
    use_provider(FakeProvider(script=[bad, bad]))
    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[0])
    inv = await _investigate(client, owner, org, inc.key, queued)
    assert inv["status"] == "failed" and inv["error_code"] == "ai.invalid_output"
    assert inv["result"] is None and inv["evidence"]  # evidence is kept for humans
    after = await client.get(f"/orgs/{org}/incidents/{inc.key}", headers=owner.h)
    assert after.json()["status"] == "triggered" and after.json()["root_cause_confirmed"] is None


@pytest.mark.parametrize("code", ["ai.rate_limited", "ai.refused", "ai.timeout"])
async def test_provider_errors_fail_gracefully_and_are_metered(
    client: httpx.AsyncClient,
    queued: list[UUID],
    use_provider: Callable[[FakeProvider], FakeProvider],
    code: str,
) -> None:
    use_provider(FakeProvider(script=[ProviderError(code, "nope", usage=Usage(321, 0))]))
    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[2])
    inv = await _investigate(client, owner, org, inc.key, queued)
    assert inv["status"] == "failed" and inv["error_code"] == code
    usage = await _usage_rows(inv["id"])
    assert [(u.outcome, u.input_tokens) for u in usage] == [(code, 321)]


# ------------------------------------------------------------------- chat + tools


async def test_follow_up_uses_read_only_tools_and_cites_new_evidence(
    client: httpx.AsyncClient,
    queued: list[UUID],
    use_provider: Callable[[FakeProvider], FakeProvider],
) -> None:
    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[0])
    inv = await _investigate(client, owner, org, inc.key, queued)
    n_before = len(inv["evidence"])
    now = datetime.now(UTC)

    tool_turn = LLMResult(
        text=None,
        tool_calls=[
            ToolCall(
                "t1",
                "search_logs",
                {
                    "service": "checkout-api",
                    "level": "error",
                    "contains": "CartSerializer",
                    "from": (now - timedelta(hours=1)).isoformat(),
                    "to": now.isoformat(),
                    "limit": 5,
                },
            ),
            ToolCall("t2", "get_incident", {"key": "INC-99999"}),  # → tool error, not a crash
        ],
        usage=Usage(800, 50),
        model="claude-opus-5-5",
        raw=["opaque-thinking-blocks"],
    )

    def answer(req: LLMRequest) -> LLMResult:
        results = req.messages[-1].tool_results
        payload = json.loads(results[0].content)
        assert results[1].is_error and "No incident" in results[1].content
        assert req.messages[-2].raw == ["opaque-thinking-blocks"]  # replayed verbatim
        new_ref = payload["evidence"][0]["ref"]
        return LLMResult(
            text=json.dumps(
                {"answer": f"Errors began with the deploy [{new_ref}]", "evidence_refs": [new_ref]}
            ),
            tool_calls=[],
            usage=Usage(900, 60),
            model="claude-opus-5-5",
        )

    fake = use_provider(FakeProvider(script=[tool_turn, answer]))
    client_id = str(uuid4())
    url = f"/orgs/{org}/ai/investigations/{inv['id']}/messages"
    r = await client.post(
        url, json={"question": "When did errors start?", "client_id": client_id}, headers=owner.h
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert [m["role"] for m in body["messages"]] == ["user", "tool", "tool", "assistant"]
    assert body["messages"][1]["tool_name"] == "search_logs"
    new = body["new_evidence"]
    assert len(new) == 1 and new[0]["kind"] == "log"
    assert new[0]["ref"] == f"EV-{n_before + 1}"
    assert body["messages"][-1]["evidence_refs"] == [new[0]["ref"]]
    assert fake.requests[0].tools and all(
        t.name
        in {
            "query_metric",
            "search_logs",
            "list_deployments",
            "get_incident",
            "find_similar_incidents",
        }
        for t in fake.requests[0].tools
    )

    # Retry with the same client_id → stored turn, no provider call.
    again = await client.post(
        url, json={"question": "When did errors start?", "client_id": client_id}, headers=owner.h
    )
    assert again.json()["messages"] == body["messages"] and len(fake.requests) == 2

    full = await client.get(f"/orgs/{org}/ai/investigations/{inv['id']}", headers=owner.h)
    assert full.json()["tool_calls_used"] == 2
    assert len(full.json()["evidence"]) == n_before + 1


async def test_failed_follow_up_keeps_usage_and_no_messages(
    client: httpx.AsyncClient,
    queued: list[UUID],
    use_provider: Callable[[FakeProvider], FakeProvider],
) -> None:
    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[1])
    inv = await _investigate(client, owner, org, inc.key, queued)
    bad = LLMResult(
        text='{"answer": "x", "evidence_refs": ["EV-404"]}',
        tool_calls=[],
        usage=Usage(100, 10),
        model="claude-opus-5-5",
    )
    use_provider(FakeProvider(script=[bad, bad]))
    r = await client.post(
        f"/orgs/{org}/ai/investigations/{inv['id']}/messages",
        json={"question": "Why?", "client_id": str(uuid4())},
        headers=owner.h,
    )
    assert r.status_code == 502 and problem(r)["code"] == "ai.invalid_output"
    msgs = await client.get(f"/orgs/{org}/ai/investigations/{inv['id']}/messages", headers=owner.h)
    assert msgs.json() == []
    outcomes = [u.outcome for u in await _usage_rows(inv["id"])]
    assert outcomes == ["ok", "invalid_output", "invalid_output"]


async def test_tool_inputs_are_validated_and_ranges_clamped(client: httpx.AsyncClient) -> None:
    _owner, org = await _ai_org(client)
    await _scenario(org, SCENARIOS[0])
    async with get_sessionmaker()() as s:
        reg = EvidenceRegistry(next_index=10)
        now = datetime.now(UTC)
        ex = ToolExecutor(s, UUID(org), reg, Redactor(), now)
        bad = [
            ToolCall(
                "a",
                "query_metric",
                {"service": "nope", "metric": "x", "aggregation": "avg", "from": "x", "to": "y"},
            ),
            ToolCall(
                "b",
                "query_metric",
                {
                    "service": "checkout-api",
                    "metric": "x",
                    "aggregation": "median",
                    "from": now.isoformat(),
                    "to": now.isoformat(),
                },
            ),
            ToolCall("c", "drop_table", {}),
            ToolCall(
                "d",
                "search_logs",
                {
                    "service": "checkout-api",
                    "level": "any",
                    "contains": None,
                    "from": now.isoformat(),
                    "to": (now - timedelta(hours=1)).isoformat(),
                    "limit": 5,
                },
            ),
        ]
        for call in bad:
            assert (await ex.run(call)).is_error, call
        ok = await ex.run(
            ToolCall(
                "e",
                "query_metric",
                {
                    "service": "checkout-api",
                    "metric": "http.server.duration_ms",
                    "aggregation": "p95",
                    "from": (now - timedelta(days=30)).isoformat(),
                    "to": (now + timedelta(days=1)).isoformat(),
                },
            )
        )
        payload = json.loads(ok.content)
        assert not ok.is_error and payload["evidence"][0]["ref"] == "EV-10"
        assert "clamped" in payload["notes"][0]
        assert reg.items[0].kind == EvidenceKind.METRIC
        assert reg.items[0].source_query["from"] >= (now - timedelta(days=7, minutes=1)).isoformat()


async def test_tools_are_tenant_scoped(client: httpx.AsyncClient) -> None:
    _, org_a = await _ai_org(client)
    _, org_b = await _ai_org(client)
    await _scenario(org_a, SCENARIOS[0])
    async with get_sessionmaker()() as s:
        ex = ToolExecutor(s, UUID(org_b), EvidenceRegistry(), Redactor(), datetime.now(UTC))
        r = await ex.run(
            ToolCall(
                "x",
                "list_deployments",
                {
                    "service": "checkout-api",
                    "from": (datetime.now(UTC) - timedelta(days=1)).isoformat(),
                    "to": datetime.now(UTC).isoformat(),
                },
            )
        )
        assert r.is_error and "No service" in r.content
        r = await ex.run(ToolCall("y", "get_incident", {"key": "INC-1001"}))
        assert r.is_error


# ------------------------------------------------------------------------ proposals


async def test_proposal_decisions_need_the_right_people(
    client: httpx.AsyncClient, queued: list[UUID], use_provider: Any
) -> None:
    use_provider(FakeProvider(script=[_scripted_valid]))
    owner, org = await _ai_org(client)
    eng = await register(client, "eng-prop@example.com")
    viewer = await register(client, "viewer-prop@example.com")
    await add_member(client, org, owner, eng, "engineer")
    await add_member(client, org, owner, viewer, "viewer")
    inc = await _scenario(org, SCENARIOS[0])
    inv = await _investigate(client, owner, org, inc.key, queued)
    by_risk = {p["risk"]: p for p in inv["proposals"]}
    assert set(by_risk) == {"sensitive", "destructive"}
    base = f"/orgs/{org}/ai/investigations/{inv['id']}/proposals"

    sens = f"{base}/{by_risk['sensitive']['id']}/decision"
    assert (await client.post(sens, json={"approve": True}, headers=viewer.h)).status_code == 403
    r = await client.post(sens, json={"approve": True, "note": "Rolling back"}, headers=eng.h)
    assert r.status_code == 200 and r.json()["status"] == "approved"
    assert r.json()["executes_automatically"] is False
    twice = await client.post(sens, json={"approve": False}, headers=eng.h)
    assert twice.status_code == 409 and problem(twice)["code"] == "ai.proposal_decided"

    destr = f"{base}/{by_risk['destructive']['id']}/decision"
    r = await client.post(destr, json={"approve": True}, headers=eng.h)
    assert r.status_code == 403 and problem(r)["code"] == "ai.destructive_requires_admin"
    r = await client.post(destr, json={"approve": False}, headers=owner.h)
    assert r.json()["status"] == "rejected"

    audit = await client.get(f"/orgs/{org}/audit-logs", headers=owner.h)
    actions = [e["action"] for e in audit.json()["items"]]
    assert "ai.proposal_approved" in actions and "ai.proposal_rejected" in actions
    timeline = await client.get(f"/orgs/{org}/incidents/{inc.key}/timeline", headers=owner.h)
    decisions = [
        e
        for e in timeline.json()["items"]
        if e["type"] == "ai_analysis" and e["data"]["kind"] == "proposal_decision"
    ]
    assert len(decisions) == 2


async def test_feedback_and_lists(
    client: httpx.AsyncClient, queued: list[UUID], use_provider: Any
) -> None:
    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[3])
    inv = await _investigate(client, owner, org, inc.key, queued)
    url = f"/orgs/{org}/ai/investigations/{inv['id']}/feedback"
    assert (await client.put(url, json={"helpful": False}, headers=owner.h)).status_code == 204
    assert (await client.put(url, json={"helpful": True}, headers=owner.h)).status_code == 204
    again = await client.get(f"/orgs/{org}/ai/investigations/{inv['id']}", headers=owner.h)
    assert again.json()["my_feedback"] is True

    listing = await client.get(f"/orgs/{org}/ai/investigations", headers=owner.h)
    item = listing.json()["items"][0]
    assert item["incident_key"] == inc.key and item["summary"]
    per_inc = await client.get(f"/orgs/{org}/incidents/{inc.key}/investigations", headers=owner.h)
    assert [i["id"] for i in per_inc.json()] == [inv["id"]]

    usage = await client.get(f"/orgs/{org}/ai/usage", headers=owner.h)
    assert usage.status_code == 200
    assert usage.json()["days"][0]["model"] == "fake-rules-v1"
    assert usage.json()["days"][0]["calls"] == 1


# ---------------------------------------------------------------------- auto trigger


async def test_auto_investigation_from_the_relay(
    client: httpx.AsyncClient, queued: list[UUID], use_provider: Any
) -> None:
    owner, org = await _ai_org(client, auto_investigate_min_severity="sev2")
    push = RecordingPushProvider()

    async def relay() -> None:
        async with get_sessionmaker()() as s:
            while await relay_once(s, get_redis(), push):
                pass

    async with get_sessionmaker()() as s:
        svc = Service(org_id=UUID(org), slug="api", name="api")
        s.add(svc)
        await s.flush()
        hot = await create_incident(
            s,
            org_id=UUID(org),
            title="hot",
            severity=Severity.SEV1,
            source=IncidentSource.ALERT,
            service_id=svc.id,
        )
        cold = await create_incident(
            s,
            org_id=UUID(org),
            title="cold",
            severity=Severity.SEV4,
            source=IncidentSource.ALERT,
            service_id=svc.id,
        )
        await s.commit()
    await relay()
    await relay()  # nothing new: no duplicate run
    assert len(queued) == 1
    runs = await client.get(f"/orgs/{org}/incidents/{hot.key}/investigations", headers=owner.h)
    assert runs.json()[0]["trigger"] == "auto"
    none = await client.get(f"/orgs/{org}/incidents/{cold.key}/investigations", headers=owner.h)
    assert none.json() == []
    await _run_all(queued)
    # The API service has no telemetry → the run fails honestly (no invented analysis).
    runs = await client.get(f"/orgs/{org}/incidents/{hot.key}/investigations", headers=owner.h)
    assert runs.json()[0]["status"] == RunStatus.FAILED.value


async def test_investigation_ids_do_not_cross_orgs(
    client: httpx.AsyncClient, queued: list[UUID], use_provider: Any
) -> None:
    owner_a, org_a = await _ai_org(client)
    owner_b, org_b = await _ai_org(client)
    inc = await _scenario(org_a, SCENARIOS[0])
    inv = await _investigate(client, owner_a, org_a, inc.key, queued)
    for method, path, body in [
        ("GET", f"/ai/investigations/{inv['id']}", None),
        ("GET", f"/ai/investigations/{inv['id']}/messages", None),
        (
            "POST",
            f"/ai/investigations/{inv['id']}/messages",
            {"question": "hi", "client_id": str(uuid4())},
        ),
        ("PUT", f"/ai/investigations/{inv['id']}/feedback", {"helpful": True}),
    ]:
        r = await client.request(method, f"/orgs/{org_b}{path}", json=body, headers=owner_b.h)
        assert r.status_code == 404, (method, path, r.text)
        assert problem(r)["code"] == "ai.investigation_not_found"


async def test_missing_baseline_is_reported_as_a_gap(
    client: httpx.AsyncClient, queued: list[UUID], use_provider: Any, db_dsn: str
) -> None:
    import asyncpg

    owner, org = await _ai_org(client)
    inc = await _scenario(org, SCENARIOS[0])
    conn = await asyncpg.connect(db_dsn)
    try:  # telemetry that only starts shortly before the incident
        await conn.execute(
            "DELETE FROM metric_rollups_1m WHERE org_id = $1 AND bucket < $2",
            UUID(org),
            inc.started_at - timedelta(minutes=15),
        )
    finally:
        await conn.close()
    inv = await _investigate(client, owner, org, inc.key, queued)
    assert inv["status"] == "succeeded"
    assert any("No baseline" in g for g in inv["result"]["data_gaps"])
    metric = next(e for e in inv["evidence"] if e["kind"] == "metric")
    assert metric["excerpt"]["baseline"] is None  # never invented
