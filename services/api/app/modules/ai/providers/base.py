"""Provider port (AI_ARCHITECTURE.md §3). Business logic depends only on these types.

Messages are provider-neutral. An assistant turn may carry `raw`: the adapter's own native
content (e.g. thinking blocks) which the *same* adapter replays verbatim on the next call;
other adapters ignore it.
"""

from dataclasses import dataclass, field
from typing import Any, Literal, Protocol


@dataclass(frozen=True)
class ToolSpec:
    name: str
    description: str
    input_schema: dict[str, Any]  # JSON Schema; additionalProperties: false, all required


@dataclass(frozen=True)
class ToolCall:
    id: str
    name: str
    input: dict[str, Any]


@dataclass(frozen=True)
class ToolResult:
    call_id: str
    content: str
    is_error: bool = False


@dataclass
class Message:
    role: Literal["user", "assistant"]
    text: str | None = None
    tool_calls: list[ToolCall] = field(default_factory=list)
    tool_results: list[ToolResult] = field(default_factory=list)
    raw: Any = None  # adapter-native content of an assistant turn


@dataclass(frozen=True)
class Usage:
    input_tokens: int = 0
    output_tokens: int = 0
    cached_tokens: int = 0  # cache reads
    cache_write_tokens: int = 0

    @property
    def total(self) -> int:
        return self.input_tokens + self.output_tokens + self.cached_tokens + self.cache_write_tokens


@dataclass(frozen=True)
class LLMRequest:
    model: str
    system: str
    messages: list[Message]
    max_output_tokens: int
    tools: list[ToolSpec] | None = None
    # JSON Schema the final answer must follow (structured output).
    response_schema: dict[str, Any] | None = None
    # Structured view of the same context, for adapters that don't call a model (the
    # FakeProvider). Real adapters only send what is rendered in `messages`.
    context: dict[str, Any] | None = None
    purpose: str = "investigate"
    # Language of the model's prose ("en", "vi"); the system prompt already says so.
    language: str = "en"


@dataclass(frozen=True)
class LLMResult:
    text: str | None
    tool_calls: list[ToolCall]
    usage: Usage
    model: str
    request_id: str | None = None
    raw: Any = None  # replayed by the same adapter on the next turn
    stop_reason: str | None = None

    @property
    def wants_tools(self) -> bool:
        return bool(self.tool_calls)


class ProviderError(Exception):
    """A provider call failed after the adapter's own retries. `code` is stable."""

    def __init__(
        self, code: str, detail: str, *, retryable: bool = False, usage: "Usage | None" = None
    ) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail
        self.retryable = retryable
        self.usage = usage  # tokens billed even though the call failed (refusal, truncation)


class LLMProvider(Protocol):
    name: str

    async def generate(self, request: LLMRequest) -> LLMResult: ...
