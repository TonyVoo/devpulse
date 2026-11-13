"""AI analyses in the user's language.

`ai_investigations.language`: the language the model writes in (the requester's UI
language; automatic runs use the org setting). `ai_settings.language`: that org setting.
Existing rows are English, as they were written.

Revision ID: 3a7c1e9d4b52
Revises: f9322e51775a
Create Date: 2026-11-13
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "3a7c1e9d4b52"
down_revision: str | None = "f9322e51775a"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    for table in ("ai_investigations", "ai_settings"):
        op.add_column(
            table, sa.Column("language", sa.String(8), server_default="en", nullable=False)
        )


def downgrade() -> None:
    for table in ("ai_investigations", "ai_settings"):
        op.drop_column(table, "language")
