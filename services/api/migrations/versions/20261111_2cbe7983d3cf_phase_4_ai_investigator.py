"""Phase 4: AI investigator (settings, investigations, evidence, messages, usage,
proposals, feedback) and the `ai_analysis` timeline event.

Revision ID: 2cbe7983d3cf
Revises: 2c0c10bc3de7
Create Date: 2026-11-11 17:56:50.912881
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "2cbe7983d3cf"
down_revision: str | None = "2c0c10bc3de7"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


AI_ENUMS = (
    "ai_trigger",
    "ai_run_status",
    "ai_risk",
    "ai_proposal_status",
    "ai_evidence_kind",
    "ai_message_role",
)


def upgrade() -> None:
    # New values can't be used inside the transaction that adds them; nothing here does.
    op.execute("ALTER TYPE incident_event_type ADD VALUE IF NOT EXISTS 'ai_analysis'")
    op.create_table(
        "ai_settings",
        sa.Column("org_id", sa.Uuid(), nullable=False),
        sa.Column("enabled", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=True),
        sa.Column("model", sa.String(length=80), nullable=True),
        sa.Column(
            "monthly_budget_micros", sa.BigInteger(), server_default="20000000", nullable=False
        ),
        sa.Column("max_tokens_per_run", sa.Integer(), server_default="200000", nullable=False),
        sa.Column(
            "auto_investigate_min_severity",
            postgresql.ENUM("sev1", "sev2", "sev3", "sev4", name="severity", create_type=False),
            nullable=True,
        ),
        sa.Column(
            "data_redaction",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text('\'{"emails": true, "ips": true, "secrets": true}\'::jsonb'),
            nullable=False,
        ),
        sa.Column("updated_by", sa.Uuid(), nullable=True),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["org_id"],
            ["organizations.id"],
            name=op.f("fk_ai_settings_org_id_organizations"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["updated_by"],
            ["users.id"],
            name=op.f("fk_ai_settings_updated_by_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("org_id", name=op.f("pk_ai_settings")),
    )
    op.create_table(
        "ai_investigations",
        sa.Column("org_id", sa.Uuid(), nullable=False),
        sa.Column("incident_id", sa.Uuid(), nullable=False),
        sa.Column("trigger", sa.Enum("auto", "manual", name="ai_trigger"), nullable=False),
        sa.Column(
            "status",
            sa.Enum(
                "queued",
                "collecting",
                "analyzing",
                "succeeded",
                "failed",
                "rejected",
                name="ai_run_status",
            ),
            nullable=False,
        ),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("model", sa.String(length=80), nullable=False),
        sa.Column("prompt_version", sa.String(length=32), nullable=False),
        sa.Column("context_hash", sa.String(length=64), nullable=True),
        sa.Column("result", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column(
            "data_gaps",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="[]",
            nullable=False,
        ),
        sa.Column("error_code", sa.String(length=64), nullable=True),
        sa.Column("error_detail", sa.Text(), nullable=True),
        sa.Column("tool_calls_used", sa.Integer(), server_default="0", nullable=False),
        sa.Column("tokens_used", sa.Integer(), server_default="0", nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("requested_by", sa.Uuid(), nullable=True),
        sa.Column("is_demo", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["incident_id"],
            ["incidents.id"],
            name=op.f("fk_ai_investigations_incident_id_incidents"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["org_id"],
            ["organizations.id"],
            name=op.f("fk_ai_investigations_org_id_organizations"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["requested_by"],
            ["users.id"],
            name=op.f("fk_ai_investigations_requested_by_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_investigations")),
    )
    op.create_index(
        "ix_ai_investigations_incident",
        "ai_investigations",
        ["org_id", "incident_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "ix_ai_investigations_org_created",
        "ai_investigations",
        ["org_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "uq_ai_investigations_active",
        "ai_investigations",
        ["incident_id"],
        unique=True,
        postgresql_where=sa.text("status IN ('queued', 'collecting', 'analyzing')"),
    )
    op.create_index(
        "uq_ai_investigations_auto",
        "ai_investigations",
        ["incident_id"],
        unique=True,
        postgresql_where=sa.text("trigger = 'auto'"),
    )
    op.create_table(
        "ai_action_proposals",
        sa.Column("org_id", sa.Uuid(), nullable=False),
        sa.Column("investigation_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column(
            "risk", sa.Enum("read_only", "sensitive", "destructive", name="ai_risk"), nullable=False
        ),
        sa.Column(
            "status",
            sa.Enum("proposed", "approved", "rejected", name="ai_proposal_status"),
            nullable=False,
        ),
        sa.Column("decided_by", sa.Uuid(), nullable=True),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("decision_note", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("clock_timestamp()"),
            nullable=False,
        ),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["decided_by"],
            ["users.id"],
            name=op.f("fk_ai_action_proposals_decided_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["investigation_id"],
            ["ai_investigations.id"],
            name=op.f("fk_ai_action_proposals_investigation_id_ai_investigations"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["org_id"],
            ["organizations.id"],
            name=op.f("fk_ai_action_proposals_org_id_organizations"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_action_proposals")),
    )
    op.create_index(
        "ix_ai_action_proposals_inv", "ai_action_proposals", ["investigation_id"], unique=False
    )
    op.create_table(
        "ai_evidence",
        sa.Column("org_id", sa.Uuid(), nullable=False),
        sa.Column("investigation_id", sa.Uuid(), nullable=False),
        sa.Column("ref", sa.String(length=16), nullable=False),
        sa.Column(
            "kind",
            sa.Enum("metric", "log", "deployment", "incident", "alert", name="ai_evidence_kind"),
            nullable=False,
        ),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("excerpt", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("source_query", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("clock_timestamp()"),
            nullable=False,
        ),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["investigation_id"],
            ["ai_investigations.id"],
            name=op.f("fk_ai_evidence_investigation_id_ai_investigations"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["org_id"],
            ["organizations.id"],
            name=op.f("fk_ai_evidence_org_id_organizations"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_evidence")),
        sa.UniqueConstraint(
            "investigation_id", "ref", name=op.f("uq_ai_evidence_investigation_id_ref")
        ),
    )
    op.create_table(
        "ai_feedback",
        sa.Column("org_id", sa.Uuid(), nullable=False),
        sa.Column("investigation_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("helpful", sa.Boolean(), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["investigation_id"],
            ["ai_investigations.id"],
            name=op.f("fk_ai_feedback_investigation_id_ai_investigations"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["org_id"],
            ["organizations.id"],
            name=op.f("fk_ai_feedback_org_id_organizations"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_ai_feedback_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("investigation_id", "user_id", name=op.f("pk_ai_feedback")),
    )
    op.create_table(
        "ai_messages",
        sa.Column("org_id", sa.Uuid(), nullable=False),
        sa.Column("investigation_id", sa.Uuid(), nullable=False),
        sa.Column(
            "role", sa.Enum("user", "assistant", "tool", name="ai_message_role"), nullable=False
        ),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column(
            "evidence_refs",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="[]",
            nullable=False,
        ),
        sa.Column("tool_name", sa.String(length=64), nullable=True),
        sa.Column("author_id", sa.Uuid(), nullable=True),
        sa.Column("client_id", sa.Uuid(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("clock_timestamp()"),
            nullable=False,
        ),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["author_id"],
            ["users.id"],
            name=op.f("fk_ai_messages_author_id_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["investigation_id"],
            ["ai_investigations.id"],
            name=op.f("fk_ai_messages_investigation_id_ai_investigations"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["org_id"],
            ["organizations.id"],
            name=op.f("fk_ai_messages_org_id_organizations"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_messages")),
        sa.UniqueConstraint("client_id", name=op.f("uq_ai_messages_client_id")),
    )
    op.create_index(
        "ix_ai_messages_thread", "ai_messages", ["investigation_id", "created_at"], unique=False
    )
    op.create_table(
        "ai_usage",
        sa.Column("org_id", sa.Uuid(), nullable=False),
        sa.Column("investigation_id", sa.Uuid(), nullable=True),
        sa.Column("purpose", sa.String(length=32), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("model", sa.String(length=80), nullable=False),
        sa.Column("input_tokens", sa.Integer(), nullable=False),
        sa.Column("output_tokens", sa.Integer(), nullable=False),
        sa.Column("cached_tokens", sa.Integer(), nullable=False),
        sa.Column("cache_write_tokens", sa.Integer(), nullable=False),
        sa.Column("cost_micros", sa.BigInteger(), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=False),
        sa.Column("attempt", sa.Integer(), nullable=False),
        sa.Column("outcome", sa.String(length=32), nullable=False),
        sa.Column("request_id", sa.String(length=80), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("clock_timestamp()"),
            nullable=False,
        ),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["investigation_id"],
            ["ai_investigations.id"],
            name=op.f("fk_ai_usage_investigation_id_ai_investigations"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["org_id"],
            ["organizations.id"],
            name=op.f("fk_ai_usage_org_id_organizations"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ai_usage")),
    )
    op.create_index("ix_ai_usage_org_created", "ai_usage", ["org_id", "created_at"], unique=False)


def downgrade() -> None:
    # ### commands auto generated by Alembic - please adjust! ###
    op.drop_index("ix_ai_usage_org_created", table_name="ai_usage")
    op.drop_table("ai_usage")
    op.drop_index("ix_ai_messages_thread", table_name="ai_messages")
    op.drop_table("ai_messages")
    op.drop_table("ai_feedback")
    op.drop_table("ai_evidence")
    op.drop_index("ix_ai_action_proposals_inv", table_name="ai_action_proposals")
    op.drop_table("ai_action_proposals")
    op.drop_index(
        "uq_ai_investigations_auto",
        table_name="ai_investigations",
        postgresql_where=sa.text("trigger = 'auto'"),
    )
    op.drop_index(
        "uq_ai_investigations_active",
        table_name="ai_investigations",
        postgresql_where=sa.text("status IN ('queued', 'collecting', 'analyzing')"),
    )
    op.drop_index("ix_ai_investigations_org_created", table_name="ai_investigations")
    op.drop_index("ix_ai_investigations_incident", table_name="ai_investigations")
    op.drop_table("ai_investigations")
    op.drop_table("ai_settings")
    for name in AI_ENUMS:
        op.execute(f"DROP TYPE IF EXISTS {name}")
    # Postgres can't drop an enum value; 'ai_analysis' stays on incident_event_type (unused).
