#!/usr/bin/env python3
"""
init_db.py

Applies all SQL migration files in migrations/ sequentially to a target PostgreSQL database.
Can be executed against a local or remote PostgreSQL instance.
"""

import os
import sys
from pathlib import Path

# Ensure UTF-8 output
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

try:
    import psycopg2
    HAS_PSYCOPG2 = True
except ImportError:
    HAS_PSYCOPG2 = False


def main():
    root_dir = Path(__file__).resolve().parent.parent
    migrations_dir = root_dir / "migrations"

    print("=" * 65)
    print(" 🛠️ INITIALIZING DATABASE MIGRATIONS")
    print("=" * 65)

    migration_files = sorted(list(migrations_dir.glob("*.sql")))
    if not migration_files:
        print("❌ No SQL migration files found in migrations/")
        return 1

    print(f"Found {len(migration_files)} migration files:\n")
    for f in migration_files:
        print(f"  ├── 📄 {f.name}")

    db_url = os.environ.get(
        "DATABASE_URL",
        "postgresql://postgres:postgres_dev_secret_change_in_prod@localhost:5432/aic_reconciliation"
    )

    if not HAS_PSYCOPG2:
        print("\n⚠️ psycopg2 is not installed. To apply migrations via Python, run:")
        print("   pip install psycopg2-binary")
        print("   Alternatively, let docker compose apply them automatically via docker-entrypoint-initdb.d/")
        return 0

    print(f"\nConnecting to: {db_url.split('@')[-1] if '@' in db_url else 'localhost'} ...")
    try:
        conn = psycopg2.connect(db_url)
        conn.autocommit = True
        cursor = conn.cursor()

        for mf in migration_files:
            print(f"Applying {mf.name} ...")
            with open(mf, "r", encoding="utf-8") as f:
                sql_content = f.read()
            cursor.execute(sql_content)
            print(f"  └── ✅ [APPLIED] {mf.name}")

        cursor.close()
        conn.close()
        print("\n" + "=" * 65)
        print(" 🎉 ALL MIGRATIONS APPLIED SUCCESSFULLY!")
        print("=" * 65)
        return 0
    except Exception as e:
        print(f"❌ Migration Error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
