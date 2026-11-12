"""Gemini adapter (official `google-genai` SDK). The API key is read from server settings only.

Free-tier note: on the Gemini API free tier Google may use requests and responses to
improve its products; the settings UI says so before an admin enables it.
"""

from typing import Any

import httpx2
import structlog
from google import genai
from google.genai import errors, types

from app.modules.ai.providers.base import (
    LLMRequest,
    LLMResult,
    Message,
    ProviderError,
    ToolCall,
    Usage,
)

log = structlog.get_logger(__name__)

_RETRYABLE = [408, 429, 500, 502, 503, 504]
_BLOCKED = {"SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "RECITATION"}


def _to_wire(messages: list[Message]) -> list[types.Content]:
    out: list[types.Content] = []
    names: dict[str, str] = {}  # tool call id → function name (Gemini answers by name)
    for m in messages:
        if m.role == "assistant":
            for c in m.tool_calls:
                names[c.id] = c.name
            # Replay our own previous content verbatim (keeps thought signatures intact).
            if m.raw is not None:
                out.append(m.raw)
            else:
                out.append(types.Content(role="model", parts=[types.Part(text=m.text or "")]))
        elif m.tool_results:
            out.append(
                types.Content(
                    role="user",
                    parts=[
                        types.Part.from_function_response(
                            name=names.get(r.call_id, "tool"),
                            response={"error": r.content} if r.is_error else {"result": r.content},
                        )
                        for r in m.tool_results
                    ],
                )
            )
        else:
            out.append(types.Content(role="user", parts=[types.Part(text=m.text or "")]))
    return out


class GeminiProvider:
    name = "gemini"

    def __init__(
        self,
        *,
        api_key: str,
        timeout_s: float,
        max_retries: int,
        client: Any = None,
    ) -> None:
        # The SDK retries 408/429/5xx with exponential backoff and jitter; the free tier's
        # per-minute limits make 429s the common case.
        self._client = client or genai.Client(
            api_key=api_key,
            http_options=types.HttpOptions(
                timeout=int(timeout_s * 1000),
                retry_options=types.HttpRetryOptions(
                    attempts=max_retries + 1, http_status_codes=_RETRYABLE
                ),
            ),
        )

    async def generate(self, request: LLMRequest) -> LLMResult:
        config: dict[str, Any] = {
            "system_instruction": request.system,
            "max_output_tokens": request.max_output_tokens,
            # We run the tool loop ourselves (budgets, evidence registration).
            "automatic_function_calling": types.AutomaticFunctionCallingConfig(disable=True),
        }
        if request.response_schema is not None:
            config["response_mime_type"] = "application/json"
            config["response_json_schema"] = request.response_schema
        if request.tools:
            config["tools"] = [
                types.Tool(
                    function_declarations=[
                        types.FunctionDeclaration(
                            name=t.name,
                            description=t.description,
                            parameters_json_schema=t.input_schema,
                        )
                        for t in request.tools
                    ]
                )
            ]
        try:
            response = await self._client.aio.models.generate_content(
                model=request.model,
                contents=_to_wire(request.messages),
                config=types.GenerateContentConfig(**config),
            )
        except errors.APIError as e:
            code = e.code
            if code == 429:
                raise ProviderError(
                    "ai.rate_limited", "Gemini rate limit (free-tier quota?)", retryable=True
                ) from e
            if code in (401, 403):
                raise ProviderError("ai.provider_auth", "Gemini rejected the API key") from e
            if code == 404:
                raise ProviderError("ai.model_not_found", f"Unknown model {request.model}") from e
            if code is not None and code >= 500:
                raise ProviderError(
                    "ai.provider_unavailable", f"Gemini error {code}", retryable=True
                ) from e
            raise ProviderError("ai.provider_rejected", str(e.message or e)) from e
        except httpx2.TimeoutException as e:
            raise ProviderError("ai.timeout", "Gemini call timed out", retryable=True) from e
        except httpx2.TransportError as e:
            raise ProviderError(
                "ai.provider_unreachable", "Could not reach Gemini", retryable=True
            ) from e

        meta = response.usage_metadata
        cached = (meta.cached_content_token_count or 0) if meta else 0
        usage = Usage(
            # prompt_token_count includes cached tokens; bill them at the cache rate.
            input_tokens=max(0, ((meta.prompt_token_count or 0) if meta else 0) - cached),
            # Thinking tokens are billed as output.
            output_tokens=((meta.candidates_token_count or 0) + (meta.thoughts_token_count or 0))
            if meta
            else 0,
            cached_tokens=cached,
        )
        candidate = response.candidates[0] if response.candidates else None
        finish = candidate.finish_reason.name if candidate and candidate.finish_reason else None
        log.info(
            "ai_provider_call",
            provider="gemini",
            model=request.model,
            finish_reason=finish,
            input_tokens=usage.input_tokens,
            output_tokens=usage.output_tokens,
            cached_tokens=usage.cached_tokens,
        )
        blocked = response.prompt_feedback and response.prompt_feedback.block_reason
        if blocked or finish in _BLOCKED or candidate is None:
            raise ProviderError(
                "ai.refused", f"Gemini declined (reason: {blocked or finish})", usage=usage
            )
        if finish == "MAX_TOKENS":
            raise ProviderError(
                "ai.truncated", "The answer hit the output token limit", usage=usage
            )

        parts = (candidate.content.parts if candidate.content else None) or []
        text = "".join(p.text for p in parts if p.text and not p.thought) or None
        calls = [
            ToolCall(
                id=p.function_call.id or f"call_{i}",
                name=p.function_call.name or "",
                input=dict(p.function_call.args or {}),
            )
            for i, p in enumerate(parts)
            if p.function_call
        ]
        return LLMResult(
            text=text,
            tool_calls=calls,
            usage=usage,
            model=request.model,
            request_id=getattr(response, "response_id", None),
            raw=candidate.content,
            stop_reason=finish,
        )
