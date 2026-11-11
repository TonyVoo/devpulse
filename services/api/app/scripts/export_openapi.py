"""Write the OpenAPI schema to a file (used by CI drift check and client generation)."""

import json
import os
import sys
from pathlib import Path

# Schema generation needs no live services; dummy values satisfy settings validation.
os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://openapi:openapi@localhost/openapi")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault("JWT_SIGNING_KEY", "openapi-export-only-not-a-secret-0123456789")

from app.main import create_app


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "openapi.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(create_app().openapi(), indent=2, sort_keys=True) + "\n")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
