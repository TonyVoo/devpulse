"""Phase 6: Postgres row-level security on tenant tables (defence in depth, ADR-026).

Every table with an `org_id` (and `organizations` itself) gets one policy: when the
transaction has set `app.org_id`, only that org's rows are visible or writable. Org-scoped
API requests set it per transaction (app/core/tenancy.py); workers and account-level
endpoints don't, and keep their explicit filters. FORCE makes the policy apply to the table
owner too. Superusers and BYPASSRLS roles are never subject to RLS — production must
connect as an ordinary role (the API logs a warning otherwise).

Revision ID: f9322e51775a
Revises: 2cbe7983d3cf
Create Date: 2026-11-12
"""

from collections.abc import Sequence

from alembic import op

revision: str = "f9322e51775a"
down_revision: str | None = "2cbe7983d3cf"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TENANT_TABLES = (
    "ai_action_proposals",
    "ai_evidence",
    "ai_feedback",
    "ai_investigations",
    "ai_messages",
    "ai_settings",
    "ai_usage",
    "alert_instances",
    "alert_rules",
    "audit_logs",
    "deployments",
    "idempotency_keys",
    "incident_comments",
    "incident_deployments",
    "incident_events",
    "incidents",
    "ingest_keys",
    "integrations",
    "invitations",
    "log_events",
    "memberships",
    "metric_points",
    "metric_rollups_1m",
    "notification_preferences",
    "outbox",
    "services",
    "webhook_deliveries",
)


def upgrade() -> None:
    # NULL when no org is set for this transaction (workers, auth): the policy then allows
    # everything and the application's own filters apply, exactly as before.
    op.execute(
        """
        CREATE FUNCTION devpulse_rls_org() RETURNS uuid
        LANGUAGE sql STABLE PARALLEL SAFE
        AS $$ SELECT NULLIF(current_setting('app.org_id', true), '')::uuid $$
        """
    )
    for table in TENANT_TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY")
        op.execute(
            f"""
            CREATE POLICY tenant_isolation ON {table}
            USING (devpulse_rls_org() IS NULL OR org_id = devpulse_rls_org())
            WITH CHECK (devpulse_rls_org() IS NULL OR org_id = devpulse_rls_org())
            """
        )
    op.execute("ALTER TABLE organizations ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE organizations FORCE ROW LEVEL SECURITY")
    op.execute(
        """
        CREATE POLICY tenant_isolation ON organizations
        USING (devpulse_rls_org() IS NULL OR id = devpulse_rls_org())
        WITH CHECK (devpulse_rls_org() IS NULL OR id = devpulse_rls_org())
        """
    )


def downgrade() -> None:
    for table in (*TENANT_TABLES, "organizations"):
        op.execute(f"DROP POLICY IF EXISTS tenant_isolation ON {table}")
        op.execute(f"ALTER TABLE {table} NO FORCE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")
    op.execute("DROP FUNCTION IF EXISTS devpulse_rls_org()")
