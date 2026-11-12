"""Claude adapter (official `anthropic` SDK). The API key is read from server settings only."""

from typing import Any

import anthropic
import structlog

from app.modules.ai.providers.base import (
    LLMRequest,
    LLMResult,
    Message,
    ProviderError,
    ToolCall,
    Usage,
)

log = structlog.get_logger(__name__)

# Server-side refusal fallback: on a policy decline the API re-runs the request on a
# fallback model inside the same call. Only these models accept the parameter.
FALLBACK_BETA = "server-side-fallback-2026-07-01"
_FALLBACK_MODELS = {
    "claude-fable-5-2",
    "claude-fable-5-1",
    "claude-opus-5-5",
    "claude-opus-5",
    "claude-sonnet-5-5",
}


def _to_wire(messages: list[Message]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for m in messages:
        if m.role == "assistant":
            # Replay our own previous content verbatim (thinking blocks must be unchanged).
            out.append({"role": "assistant", "content": m.raw if m.raw is not None else m.text})
        elif m.tool_results:
            out.append(
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": r.call_id,
                            "content": r.content,
                            "is_error": r.is_error,
                        }
                        for r in m.tool_results
                    ],
                }
            )
        else:
            out.append({"role": "user", "content": m.text or ""})
    return out


class AnthropicProvider:
    name = "anthropic"

    def __init__(
        self,
        *,
        api_key: str,
        timeout_s: float,
        max_retries: int,
        effort: str,
        client: anthropic.AsyncAnthropic | None = None,
    ) -> None:
        # The SDK retries connection errors, 408/409/429 and 5xx with exponential backoff
        # and jitter; `max_retries` is our retry policy (AI_ARCHITECTURE.md §6).
        self._client = client or anthropic.AsyncAnthropic(
            api_key=api_key, timeout=timeout_s, max_retries=max_retries
        )
        self._effort = effort

    async def generate(self, request: LLMRequest) -> LLMResult:
        output_config: dict[str, Any] = {"effort": self._effort}
        if request.response_schema is not None:
            output_config["format"] = {"type": "json_schema", "schema": request.response_schema}
        kwargs: dict[str, Any] = {
            "model": request.model,
            "max_tokens": request.max_output_tokens,
            # Frozen system prompt first: tools + system form a stable, cacheable prefix.
            "system": [
                {"type": "text", "text": request.system, "cache_control": {"type": "ephemeral"}}
            ],
            "messages": _to_wire(request.messages),
            "output_config": output_config,
        }
        if request.tools:
            kwargs["tools"] = [
                {
                    "name": t.name,
                    "description": t.description,
                    "input_schema": t.input_schema,
                    "strict": True,
                }
                for t in request.tools
            ]
        if request.model in _FALLBACK_MODELS:
            kwargs["betas"] = [FALLBACK_BETA]
            kwargs["fallbacks"] = "default"

        try:
            response = await self._client.beta.messages.create(**kwargs)
        except anthropic.AuthenticationError as e:
            raise ProviderError("ai.provider_auth", "The AI provider rejected the API key") from e
        except anthropic.PermissionDeniedError as e:
            raise ProviderError("ai.provider_auth", "The API key lacks permission") from e
        except anthropic.NotFoundError as e:
            raise ProviderError("ai.model_not_found", f"Unknown model {request.model}") from e
        except anthropic.BadRequestError as e:
            raise ProviderError("ai.provider_rejected", e.message) from e
        except anthropic.RateLimitError as e:
            raise ProviderError("ai.rate_limited", "Provider rate limit", retryable=True) from e
        except anthropic.APIStatusError as e:
            raise ProviderError(
                "ai.provider_unavailable", f"Provider error {e.status_code}", retryable=True
            ) from e
        except anthropic.APITimeoutError as e:
            raise ProviderError("ai.timeout", "Provider call timed out", retryable=True) from e
        except anthropic.APIConnectionError as e:
            raise ProviderError(
                "ai.provider_unreachable", "Could not reach the provider", retryable=True
            ) from e

        # Set by the SDK on real responses (the `request-id` header); log it on failures.
        request_id: str | None = getattr(response, "_request_id", None)
        usage = Usage(
            input_tokens=response.usage.input_tokens or 0,
            output_tokens=response.usage.output_tokens or 0,
            cached_tokens=response.usage.cache_read_input_tokens or 0,
            cache_write_tokens=response.usage.cache_creation_input_tokens or 0,
        )
        log.info(
            "ai_provider_call",
            model=response.model,
            stop_reason=response.stop_reason,
            request_id=request_id,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cached_tokens=usage.cached_tokens,
        )
        if response.stop_reason == "refusal":
            category = response.stop_details.category if response.stop_details else None
            raise ProviderError(
                "ai.refused", f"The model declined (category: {category})", usage=usage
            )
        if response.stop_reason == "max_tokens":
            raise ProviderError(
                "ai.truncated", "The answer hit the output token limit", usage=usage
            )

        text = "".join(b.text for b in response.content if b.type == "text") or None
        calls = [
            ToolCall(id=b.id, name=b.name, input=dict(b.input))
            for b in response.content
            if b.type == "tool_use"
        ]
        return LLMResult(
            text=text,
            tool_calls=calls,
            usage=usage,
            model=response.model,
            request_id=request_id,
            raw=list(response.content),
            stop_reason=response.stop_reason,
        )
