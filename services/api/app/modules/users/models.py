from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, Timestamps, UUIDPk


class User(UUIDPk, Timestamps, Base):
    __tablename__ = "users"

    # Stored normalised (lower-cased, trimmed); uniqueness is on the normalised value.
    email: Mapped[str] = mapped_column(String(320), unique=True)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(120))
    avatar_url: Mapped[str | None] = mapped_column(String(1024))
    theme_pref: Mapped[str] = mapped_column(
        Enum("system", "dark", "light", name="theme_pref"),
        default="system",
        server_default="system",
    )
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Access tokens issued before this instant are rejected (password change, "log out everywhere").
    tokens_valid_after: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    disabled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Device(UUIDPk, Timestamps, Base):
    __tablename__ = "devices"

    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    platform: Mapped[str] = mapped_column(Enum("ios", "android", "web", name="device_platform"))
    fcm_token: Mapped[str] = mapped_column(String(4096), unique=True)
    app_version: Mapped[str | None] = mapped_column(String(32))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
