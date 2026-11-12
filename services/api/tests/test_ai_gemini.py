"""Gemini adapter against a stubbed SDK client: wire format and error mapping only.
No network, no API key."""

import json
from typing import Any

import httpx2
import pytest
from google.genai import errors, types

from app.modules.ai.output import ANALYSIS_SCHEMA, validate_answer
from app.modules.ai.providers.base import LLMRequest, Message, ProviderError, ToolResult
from app.modules.ai.providers.gemini import GeminiProvider
from app.modules.ai.tools import TOOLS


class _Models:
    def __init__(self, reply: Any) -> None:
        self.reply = reply
        self.calls: list[dict[str, Any]] = []

    async def generate_content(self, **kwargs: Any) -> Any:
        self.calls.append(kwargs)
        if isinstance(self.reply, Exception):
            raise self.reply
        return self.reply


class _Client:
    def __init__(self, reply: Any) -> None:
        self.aio = type("Aio", (), {})()
        self.aio.models = _Models(reply)


def _response(parts: list[types.Part], finish: str = "STOP", block: str | None = None) -> Any:
    return types.GenerateContentResponse(
        candidates=[
            types.Candidate(
                content=types.Content(role="model", parts=parts),
                finish_reason=types.FinishReason(finish),
            )
        ]
        if not block
        else [],
        prompt_feedback=types.GenerateContentResponsePromptFeedback(block_reason=block)
        if block
        else None,
        usage_metadata=types.GenerateContentResponseUsageMetadata(
            prompt_token_count=5000,
            cached_content_token_count=4000,
            candidates_token_count=300,
            thoughts_token_count=200,
        ),
    )


def _provider(reply: Any) -> tuple[GeminiProvider, _Models]:
    client = _Client(reply)
    return GeminiProvider(
        api_key="unused", timeout_s=45, max_retries=2, client=client
    ), client.aio.models


def _request(**over: Any) -> LLMRequest:
    base: dict[str, Any] = {
        "model": "gemini-3.8-flash",
        "system": "SYSTEM",
        "messages": [Message("user", text="hello")],
        "max_output_tokens": 16000,
        "response_schema": ANALYSIS_SCHEMA,
    }
    base.update(over)
    return LLMRequest(**base)


async def test_request_shape_and_usage() -> None:
    p, models = _provider(_response([types.Part(text='{"ok": true}')]))
    result = await p.generate(_request(tools=TOOLS))
    sent = models.calls[0]
    cfg: types.GenerateContentConfig = sent["config"]
    assert sent["model"] == "gemini-3.8-flash"
    assert cfg.system_instruction == "SYSTEM" and cfg.max_output_tokens == 16000
    assert cfg.response_mime_type == "application/json"
    assert cfg.response_json_schema == ANALYSIS_SCHEMA
    assert cfg.automatic_function_calling and cfg.automatic_function_calling.disable is True
    decls = cfg.tools[0].function_declarations  # type: ignore[index,union-attr]
    assert {d.name for d in decls} == {t.name for t in TOOLS}
    assert result.text == '{"ok": true}'
    # Cached prompt tokens are split out; thinking tokens count as output.
    assert (result.usage.input_tokens, result.usage.cached_tokens, result.usage.output_tokens) == (
        1000,
        4000,
        500,
    )


async def test_tool_round_trip_replays_raw_content_and_names_results() -> None:
    call = types.Part(
        function_call=types.FunctionCall(id="fc1", name="get_incident", args={"key": "INC-1"}),
        thought_signature=b"sig",
    )
    p, models = _provider(_response([call]))
    first = await p.generate(_request(tools=TOOLS))
    assert [(c.id, c.name, c.input) for c in first.tool_calls] == [
        ("fc1", "get_incident", {"key": "INC-1"})
    ]
    await p.generate(
        _request(
            tools=TOOLS,
            messages=[
                Message("user", text="hello"),
                Message("assistant", raw=first.raw, tool_calls=first.tool_calls),
                Message("user", tool_results=[ToolResult("fc1", json.dumps({"x": 1}))]),
            ],
        )
    )
    wire = models.calls[1]["contents"]
    assert wire[1] is first.raw  # thought signature kept
    fr = wire[2].parts[0].function_response
    assert fr.name == "get_incident" and fr.response == {"result": '{"x": 1}'}


async def test_blocked_and_truncated_keep_usage() -> None:
    p, _ = _provider(_response([], block="SAFETY"))
    with pytest.raises(ProviderError) as e:
        await p.generate(_request())
    assert e.value.code == "ai.refused"
    p, _ = _provider(_response([types.Part(text="{")], finish="MAX_TOKENS"))
    with pytest.raises(ProviderError) as e:
        await p.generate(_request())
    assert e.value.code == "ai.truncated" and e.value.usage and e.value.usage.output_tokens == 500


@pytest.mark.parametrize(
    ("error", "code", "retryable"),
    [
        (lambda: errors.ClientError(429, {"error": {"message": "quota"}}), "ai.rate_limited", True),
        (
            lambda: errors.ClientError(403, {"error": {"message": "bad key"}}),
            "ai.provider_auth",
            False,
        ),
        (
            lambda: errors.ClientError(404, {"error": {"message": "no model"}}),
            "ai.model_not_found",
            False,
        ),
        (
            lambda: errors.ClientError(400, {"error": {"message": "bad"}}),
            "ai.provider_rejected",
            False,
        ),
        (
            lambda: errors.ServerError(503, {"error": {"message": "busy"}}),
            "ai.provider_unavailable",
            True,
        ),
        (lambda: httpx2.ReadTimeout("slow"), "ai.timeout", True),
        (lambda: httpx2.ConnectError("down"), "ai.provider_unreachable", True),
    ],
)
async def test_error_mapping(error: Any, code: str, retryable: bool) -> None:
    p, _ = _provider(error())
    with pytest.raises(ProviderError) as e:
        await p.generate(_request())
    assert (e.value.code, e.value.retryable) == (code, retryable)


def test_fenced_json_is_accepted() -> None:
    fenced = '```json\n{"answer": "see EV-1", "evidence_refs": ["EV-1"]}\n```'
    assert validate_answer(fenced, known_refs={"EV-1"}).evidence_refs == ["EV-1"]
