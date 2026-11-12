"""Provider selection. Adding a provider = one adapter + one entry here; no business logic
changes (AI_ARCHITECTURE.md §3)."""

from collections.abc import Callable

from app.core.config import Settings, get_settings
from app.core.errors import AppError
from app.modules.ai.providers.base import LLMProvider

PROVIDERS = ("gemini", "anthropic", "fake")


class ProviderUnavailable(AppError):
    status = 503
    title = "AI provider unavailable"


def available(settings: Settings | None = None) -> dict[str, bool]:
    s = settings or get_settings()
    return {
        "gemini": s.gemini_api_key is not None,
        "anthropic": s.anthropic_api_key is not None,
        "fake": s.ai_fake_enabled and not s.is_production,
    }


def _build(name: str) -> LLMProvider:
    s = get_settings()
    if not available(s).get(name):
        raise ProviderUnavailable(
            f"AI provider '{name}' is not configured on this server",
            code="ai.provider_unconfigured",
        )
    if name == "gemini":
        from app.modules.ai.providers.gemini import GeminiProvider

        gkey = s.gemini_api_key
        if gkey is None:  # unreachable: available() checked it
            raise ProviderUnavailable("No Gemini API key", code="ai.provider_unconfigured")
        return GeminiProvider(
            api_key=gkey.get_secret_value(),
            timeout_s=s.ai_call_timeout_s,
            max_retries=s.ai_max_retries,
        )
    if name == "anthropic":
        from app.modules.ai.providers.anthropic import AnthropicProvider

        key = s.anthropic_api_key
        if key is None:  # unreachable: available() checked it
            raise ProviderUnavailable("No Anthropic API key", code="ai.provider_unconfigured")
        return AnthropicProvider(
            api_key=key.get_secret_value(),
            timeout_s=s.ai_call_timeout_s,
            max_retries=s.ai_max_retries,
            effort=s.ai_effort,
        )
    from app.modules.ai.providers.fake import FakeProvider

    return FakeProvider()


# Tests replace this to inject a scripted FakeProvider.
provider_factory: Callable[[str], LLMProvider] = _build


def get_provider(name: str) -> LLMProvider:
    return provider_factory(name)
