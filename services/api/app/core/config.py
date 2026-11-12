"""Application settings, validated at startup. Missing/invalid values abort boot."""

from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

Env = Literal["local", "test", "staging", "production"]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: Env = "local"
    app_name: str = "devpulse-api"
    log_level: str = "INFO"
    log_json: bool = True

    database_url: str = Field(..., description="postgresql+asyncpg://...")
    redis_url: str = Field(..., description="redis://host:port/db")

    jwt_signing_key: SecretStr = Field(..., min_length=32)
    jwt_issuer: str = "devpulse"
    jwt_audience: str = "devpulse-api"
    access_token_ttl_s: int = Field(900, ge=60, le=3600)
    refresh_token_ttl_s: int = Field(60 * 60 * 24 * 30, ge=3600)
    # A just-rotated refresh token may be presented again within this window (parallel
    # requests, multiple tabs, a retried request whose response was lost) without being
    # treated as theft. Trade-off documented in DECISIONS.md (ADR-003).
    refresh_reuse_grace_s: int = Field(10, ge=0, le=60)
    invitation_ttl_s: int = Field(60 * 60 * 24 * 7, ge=3600)

    cors_origins: list[str] = []
    login_rate_limit: int = Field(10, ge=1, description="attempts per window per email+ip")
    login_rate_window_s: int = Field(300, ge=10)

    sentry_dsn: str | None = None

    # Fernet key for integration secrets (`python -c "from cryptography.fernet import
    # Fernet; print(Fernet.generate_key().decode())"`). Integrations are disabled without it.
    encryption_key: SecretStr | None = None

    ingest_rate_limit_per_min: int = Field(1200, ge=1)
    ingest_max_points: int = Field(1000, ge=1, le=10000)
    ingest_max_past_s: int = Field(3600, ge=60)
    ingest_max_future_s: int = Field(300, ge=0)

    # --- AI investigator (docs/AI_ARCHITECTURE.md). Provider keys live only here, on the
    # server; they are never returned by the API or sent to clients.
    ai_default_provider: Literal["gemini", "anthropic", "fake"] = "gemini"
    # Free tier available on the Gemini API (Google AI Studio key).
    ai_default_model: str = "gemini-3.8-flash"
    gemini_api_key: SecretStr | None = None
    anthropic_api_key: SecretStr | None = None
    # The FakeProvider produces deterministic, rule-based analyses for tests and offline
    # demos. It is labelled as such everywhere and refused in production.
    ai_fake_enabled: bool = False
    ai_call_timeout_s: float = Field(45.0, gt=0, le=300)
    ai_run_timeout_s: float = Field(90.0, gt=0, le=600)
    ai_max_retries: int = Field(2, ge=0, le=5)
    ai_effort: Literal["low", "medium", "high", "xhigh", "max"] = "high"
    # USD per million tokens: input, output, cache read, cache write. Used to compute
    # cost_micros (1 micro = $0.000001). Override with AI_PRICING='{"model": [..]}'.
    # List prices (paid tier). On the Gemini free tier nothing is billed; set AI_PRICING to
    # zeros if you want the budget to track actual spend instead.
    ai_pricing: dict[str, tuple[float, float, float, float]] = {
        "gemini-3.8-flash": (0.75, 3.75, 0.075, 0.75),
        "gemini-3.6-flash": (0.75, 3.75, 0.075, 0.75),
        "gemini-3.5-flash-lite": (0.30, 2.50, 0.03, 0.30),
        "gemini-3.1-flash-lite": (0.25, 1.50, 0.025, 0.25),
        "claude-opus-5-5": (4.0, 20.0, 0.20, 5.0),
        "claude-sonnet-5-5": (2.0, 10.0, 0.10, 2.5),
        "claude-haiku-5-5": (0.10, 0.50, 0.01, 0.125),
        "fake-rules-v1": (0.0, 0.0, 0.0, 0.0),
    }

    @field_validator("database_url")
    @classmethod
    def _async_driver(cls, v: str) -> str:
        if not v.startswith("postgresql+asyncpg://"):
            raise ValueError("DATABASE_URL must use the postgresql+asyncpg:// driver")
        return v

    @field_validator("anthropic_api_key", "gemini_api_key", mode="before")
    @classmethod
    def _blank_key_is_none(cls, v: object) -> object:
        # `ANTHROPIC_API_KEY=` in an env file means "not configured", not an empty key.
        return None if isinstance(v, str) and not v.strip() else v

    @model_validator(mode="after")
    def _production_guards(self) -> "Settings":
        if self.app_env == "production" and self.jwt_signing_key.get_secret_value().startswith(
            "change-me"
        ):
            raise ValueError("JWT_SIGNING_KEY must be a real secret in production")
        if self.app_env == "production" and self.ai_fake_enabled:
            raise ValueError("AI_FAKE_ENABLED must not be set in production")
        return self

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
