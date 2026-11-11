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

    @field_validator("database_url")
    @classmethod
    def _async_driver(cls, v: str) -> str:
        if not v.startswith("postgresql+asyncpg://"):
            raise ValueError("DATABASE_URL must use the postgresql+asyncpg:// driver")
        return v

    @model_validator(mode="after")
    def _production_guards(self) -> "Settings":
        if self.app_env == "production" and self.jwt_signing_key.get_secret_value().startswith(
            "change-me"
        ):
            raise ValueError("JWT_SIGNING_KEY must be a real secret in production")
        return self

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
