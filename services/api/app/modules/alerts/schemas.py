from datetime import datetime
from typing import Annotated, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from app.modules.alerts.models import Aggregation, AlertState, Comparator, Severity

ERROR_RATE = "http.server.error_rate"

MetricName = Annotated[
    str, StringConstraints(min_length=1, max_length=120, pattern=r"^[a-zA-Z][a-zA-Z0-9_.]*$")
]


def _check_metric(metric: str | None, aggregation: Aggregation | None) -> None:
    if metric is None or aggregation is None:
        return
    if (metric == ERROR_RATE) != (aggregation == Aggregation.RATIO):
        raise ValueError(f"use aggregation 'ratio' with {ERROR_RATE} (and only with it)")


class AlertRuleIn(BaseModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
    service_id: UUID
    metric: MetricName
    aggregation: Aggregation
    comparator: Comparator
    threshold: float = Field(allow_inf_nan=False)
    window_s: int = Field(300, ge=60, le=3600)
    for_s: int = Field(0, ge=0, le=3600)
    severity: Severity
    enabled: bool = True

    @model_validator(mode="after")
    def _metric_matches_aggregation(self) -> Self:
        _check_metric(self.metric, self.aggregation)
        return self


class AlertRuleUpdateIn(BaseModel):
    name: (
        Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
        | None
    ) = None
    metric: MetricName | None = None
    aggregation: Aggregation | None = None
    comparator: Comparator | None = None
    threshold: float | None = Field(None, allow_inf_nan=False)
    window_s: int | None = Field(None, ge=60, le=3600)
    for_s: int | None = Field(None, ge=0, le=3600)
    severity: Severity | None = None
    enabled: bool | None = None


class AlertRuleOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    service_id: UUID
    metric: str
    aggregation: Aggregation
    comparator: Comparator
    threshold: float
    window_s: int
    for_s: int
    severity: Severity
    enabled: bool
    version: int
    created_at: datetime
    updated_at: datetime
    state: AlertState | None = None
    last_value: float | None = None


class PreviewPoint(BaseModel):
    at: datetime
    value: float | None
    breached: bool


class PreviewOut(BaseModel):
    """Would the rule have fired over the last 24h? (evaluated every 5 minutes)"""

    points: list[PreviewPoint]
    breach_windows: int
