"""Telemetry storage (ADR-002).

Raw points and logs live in daily RANGE partitions (created by the partition maintenance
task; a DEFAULT partition catches anything outside the prepared window). They are Core
tables, not ORM entities: they are written in bulk and read with aggregates.
"""

from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    DateTime,
    Double,
    Index,
    PrimaryKeyConstraint,
    String,
    Table,
    Text,
    Uuid,
)
from sqlalchemy.dialects.postgresql import JSONB

from app.core.db import Base

metric_points = Table(
    "metric_points",
    Base.metadata,
    Column("org_id", Uuid, nullable=False),
    Column("service_id", Uuid, nullable=False),
    Column("name", String(120), nullable=False),
    Column("ts", DateTime(timezone=True), nullable=False),
    Column("value", Double, nullable=False),
    Column("labels", JSONB, nullable=False, server_default="{}"),
    Column("is_demo", Boolean, nullable=False, server_default="false"),
    Index("ix_metric_points_lookup", "org_id", "service_id", "name", "ts"),
    postgresql_partition_by="RANGE (ts)",
)

metric_rollups_1m = Table(
    "metric_rollups_1m",
    Base.metadata,
    Column("org_id", Uuid, nullable=False),
    Column("service_id", Uuid, nullable=False),
    Column("name", String(120), nullable=False),
    Column("bucket", DateTime(timezone=True), nullable=False),
    Column("count", BigInteger, nullable=False),
    Column("sum", Double, nullable=False),
    Column("min", Double, nullable=False),
    Column("max", Double, nullable=False),
    Column("p50", Double, nullable=False),
    Column("p95", Double, nullable=False),
    Column("p99", Double, nullable=False),
    Column("is_demo", Boolean, nullable=False, server_default="false"),
    PrimaryKeyConstraint("org_id", "service_id", "name", "bucket"),
)

log_events = Table(
    "log_events",
    Base.metadata,
    Column("org_id", Uuid, nullable=False),
    Column("service_id", Uuid, nullable=False),
    Column("ts", DateTime(timezone=True), nullable=False),
    Column("level", String(16), nullable=False),
    Column("message", Text, nullable=False),
    Column("attributes", JSONB, nullable=False, server_default="{}"),
    Column("trace_id", String(64)),
    Column("fingerprint", String(64), nullable=False),
    Column("is_demo", Boolean, nullable=False, server_default="false"),
    Index("ix_log_events_lookup", "org_id", "service_id", "ts"),
    postgresql_partition_by="RANGE (ts)",
)

PARTITIONED_TABLES = ("metric_points", "log_events")
