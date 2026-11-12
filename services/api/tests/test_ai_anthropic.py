"""Anthropic adapter against a stubbed SDK client: wire format and error mapping only.
No network, no API key."""

import json
from typing import Any

import anthropic
import httpx2
import pytest
from anthropic.types.beta import BetaMessage

from app.modules.ai.output import ANALYSIS_SCHEMA
from app.modules.ai.providers.anthropic import FALLBACK_BETA, AnthropicProvider
from app.modules.ai.providers.base import (
    LLMRequest,
    Message,
    ProviderError,
    ToolResult,
)
from app.modules.ai.tools import TOOLS


class _Messages:
    def __init__(self, reply: Any) -> None:
        self.reply = reply
        self.calls: list[dict[str, Any]] = []

    async def create(self, **kwargs: Any) -> Any:
        self.calls.append(kwargs)
        if isinstance(self.reply, Exception):
            raise self.reply
        return self.reply


class _Client:
    def __init__(self, reply: Any) -> None:
        self.beta = type("B", (), {})()
        self.beta.messages = _Messages(reply)


def _message(
    content: list[dict[str, Any]], stop: str = "end_turn", model: str = "claude-opus-5-5"
) -> BetaMessage:
    return BetaMessage.model_validate(
        {
            "id": "msg_1",
            "type": "message",
            "role": "assistant",
            "model": model,
            "content": content,
            "stop_reason": stop,
            "stop_sequence": None,
            "usage": {
                "input_tokens": 1200,
                "output_tokens": 300,
                "cache_read_input_tokens": 4000,
                "cache_creation_input_tokens": 0,
            },
        }
    )


def _provider(reply: Any) -> tuple[AnthropicProvider, _Messages]:
    client = _Client(reply)
    p = AnthropicProvider(
        api_key="unused", timeout_s=45, max_retries=2, effort="high", client=client
    )  # type: ignore[arg-type]
    return p, client.beta.messages


def _request(**over: Any) -> LLMRequest:
    base: dict[str, Any] = {
        "model": "claude-opus-5-5",
        "system": "SYSTEM",
        "messages": [Message("user", text="hello")],
        "max_output_tokens": 16000,
        "response_schema": ANALYSIS_SCHEMA,
    }
    base.update(over)
    return LLMRequest(**base)


async def test_request_shape() -> None:
    p, msgs = _provider(_message([{"type": "text", "text": '{"ok": true}'}]))
    result = await p.generate(_request(tools=TOOLS))
    sent = msgs.calls[0]
    assert sent["model"] == "claude-opus-5-5" and sent["max_tokens"] == 16000
    assert sent["system"][0]["cache_control"] == {"type": "ephemeral"}
    assert sent["output_config"]["effort"] == "high"
    assert sent["output_config"]["format"]["schema"] == ANALYSIS_SCHEMA
    assert all(t["strict"] is True for t in sent["tools"])
    assert {t["name"] for t in sent["tools"]} == {t.name for t in TOOLS}
    assert sent["betas"] == [FALLBACK_BETA] and sent["fallbacks"] == "default"
    # No sampling parameters, no thinking override (adaptive by default on this model).
    assert not {"temperature", "top_p", "top_k", "thinking"} & set(sent)
    assert result.text == '{"ok": true}'
    assert (result.usage.input_tokens, result.usage.cached_tokens) == (1200, 4000)


async def test_no_fallback_param_for_models_without_it() -> None:
    p, msgs = _provider(_message([{"type": "text", "text": "{}"}], model="claude-haiku-5-5"))
    await p.generate(_request(model="claude-haiku-5-5"))
    assert "fallbacks" not in msgs.calls[0] and "betas" not in msgs.calls[0]


async def test_tool_round_trip_replays_raw_content() -> None:
    reply = _message(
        [
            {"type": "thinking", "thinking": "", "signature": "sig"},
            {"type": "tool_use", "id": "tu_1", "name": "get_incident", "input": {"key": "INC-1"}},
        ],
        stop="tool_use",
    )
    p, msgs = _provider(reply)
    first = await p.generate(_request(tools=TOOLS))
    assert [c.name for c in first.tool_calls] == ["get_incident"]
    follow = _request(
        tools=TOOLS,
        messages=[
            Message("user", text="hello"),
            Message("assistant", raw=first.raw, tool_calls=first.tool_calls),
            Message("user", tool_results=[ToolResult("tu_1", json.dumps({"x": 1}))]),
        ],
    )
    await p.generate(follow)
    wire = msgs.calls[1]["messages"]
    assert wire[1]["content"] is first.raw  # thinking block passed back unchanged
    assert wire[2]["content"][0] == {
        "type": "tool_result",
        "tool_use_id": "tu_1",
        "content": '{"x": 1}',
        "is_error": False,
    }


async def test_refusal_and_truncation_keep_usage() -> None:
    p, _ = _provider(_message([], stop="refusal"))
    with pytest.raises(ProviderError) as e:
        await p.generate(_request())
    assert e.value.code == "ai.refused" and e.value.usage and e.value.usage.input_tokens == 1200
    p, _ = _provider(_message([{"type": "text", "text": "{"}], stop="max_tokens"))
    with pytest.raises(ProviderError) as e:
        await p.generate(_request())
    assert e.value.code == "ai.truncated"


def _status_error(cls: type[anthropic.APIStatusError], status: int) -> anthropic.APIStatusError:
    req = httpx2.Request("POST", "https://api.anthropic.com/v1/messages")
    return cls("error", response=httpx2.Response(status, request=req), body=None)


@pytest.mark.parametrize(
    ("error", "code", "retryable"),
    [
        (lambda: _status_error(anthropic.RateLimitError, 429), "ai.rate_limited", True),
        (lambda: _status_error(anthropic.AuthenticationError, 401), "ai.provider_auth", False),
        (lambda: _status_error(anthropic.BadRequestError, 400), "ai.provider_rejected", False),
        (
            lambda: _status_error(anthropic.InternalServerError, 500),
            "ai.provider_unavailable",
            True,
        ),
        (
            lambda: anthropic.APITimeoutError(
                request=httpx2.Request("POST", "https://api.anthropic.com")
            ),
            "ai.timeout",
            True,
        ),
        (
            lambda: anthropic.APIConnectionError(
                request=httpx2.Request("POST", "https://api.anthropic.com")
            ),
            "ai.provider_unreachable",
            True,
        ),
    ],
)
async def test_error_mapping(error: Any, code: str, retryable: bool) -> None:
    p, _ = _provider(error())
    with pytest.raises(ProviderError) as e:
        await p.generate(_request())
    assert (e.value.code, e.value.retryable) == (code, retryable)
