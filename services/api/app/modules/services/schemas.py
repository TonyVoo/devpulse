from datetime import datetime
from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, StringConstraints

from app.modules.services.models import Health, Tier

ServiceSlug = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        to_lower=True,
        min_length=2,
        max_length=64,
        pattern=r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$",
    ),
]
Environment = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True, to_lower=True, min_length=2, max_length=32, pattern=r"^[a-z0-9-]+$"
    ),
]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]

IngestScope = Literal["metrics:write", "logs:write", "deployments:write", "services:autocreate"]


class ServiceCreateIn(BaseModel):
    name: Name
    slug: ServiceSlug | None = None
    environment: Environment = "production"
    tier: Tier = Tier.HIGH
    description: Annotated[str, StringConstraints(max_length=2000)] | None = None
    owner_team: Annotated[str, StringConstraints(max_length=80)] | None = None
    repo_url: HttpUrl | None = None
    tags: dict[str, str] = Field(default_factory=dict, max_length=20)


class ServiceUpdateIn(BaseModel):
    name: Name | None = None
    tier: Tier | None = None
    description: Annotated[str, StringConstraints(max_length=2000)] | None = None
    owner_team: Annotated[str, StringConstraints(max_length=80)] | None = None
    repo_url: HttpUrl | None = None
    tags: dict[str, str] | None = Field(default=None, max_length=20)


class ServiceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    slug: str
    name: str
    description: str | None
    environment: str
    tier: Tier
    owner_team: str | None
    repo_url: str | None
    health: Health
    health_changed_at: datetime | None
    last_seen_at: datetime | None
    tags: dict[str, Any]
    is_demo: bool
    version: int
    created_at: datetime
    updated_at: datetime


def _default_scopes() -> list[IngestScope]:
    return ["metrics:write", "logs:write", "deployments:write"]


class IngestKeyCreateIn(BaseModel):
    name: Name
    service_id: UUID | None = None
    scopes: list[IngestScope] = Field(
        default_factory=_default_scopes,
        min_length=1,
    )


class IngestKeyOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    prefix: str
    service_id: UUID | None
    scopes: list[str]
    is_demo: bool
    last_used_at: datetime | None
    revoked_at: datetime | None
    created_at: datetime


class IngestKeyCreatedOut(IngestKeyOut):
    key: str = Field(description="Shown once. Store it in your service's secret manager.")
