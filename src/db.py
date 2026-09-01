"""Build and open the DuckDB database.

Pipeline:
  1. ``load_raw``      - read the 9 Kaggle CSVs into tables (names verbatim).
  2. ``build_staging`` - execute ``sql/00_staging.sql`` to create the stg_* views.
  3. ``get_connection``- open the built database read-only for analysis.

``build_database`` runs 1 + 2 and is what ``run_all.py`` calls.
"""

from __future__ import annotations

import sys
from pathlib import Path

import duckdb

from .config import DB_PATH, RAW_DIR, RAW_TABLES, SQL_DIR


def _require_raw_csvs() -> None:
    missing = [name for name, fn in RAW_TABLES.items() if not (RAW_DIR / fn).exists()]
    if missing:
        raise FileNotFoundError(
            "Missing raw CSVs in "
            f"{RAW_DIR}:\n  " + "\n  ".join(RAW_TABLES[m] for m in missing)
            + "\n\nRun:  python scripts/download_data.py"
        )


def load_raw(con: duckdb.DuckDBPyConnection) -> None:
    """Create one table per CSV. read_csv_auto handles the type sniffing;
    we force a few columns that DuckDB otherwise guesses wrong."""
    _require_raw_csvs()
    for table, filename in RAW_TABLES.items():
        path = (RAW_DIR / filename).as_posix()
        con.execute(
            f"CREATE OR REPLACE TABLE {table} AS "
            f"SELECT * FROM read_csv_auto('{path}', header = true, "
            f"sample_size = -1)"
        )
        n = con.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
        print(f"  loaded {table:<38} {n:>8,} rows")


def build_staging(con: duckdb.DuckDBPyConnection) -> None:
    """Execute sql/00_staging.sql - the cleaned stg_* views."""
    staging_sql = (SQL_DIR / "00_staging.sql").read_text(encoding="utf-8")
    con.execute(staging_sql)
    print("  built staging views: " + ", ".join(_staging_view_names(con)))


def _staging_view_names(con: duckdb.DuckDBPyConnection) -> list[str]:
    rows = con.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_name LIKE 'stg_%' ORDER BY table_name"
    ).fetchall()
    return [r[0] for r in rows]


def build_database(db_path: Path = DB_PATH) -> Path:
    """Full rebuild: drop the file, load CSVs, build staging. Returns the path."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()
    print(f"Building {db_path} ...")
    with duckdb.connect(str(db_path)) as con:
        load_raw(con)
        build_staging(con)
    print("Done.")
    return db_path


def get_connection(db_path: Path = DB_PATH, read_only: bool = True) -> duckdb.DuckDBPyConnection:
    """Open the built database. Rebuild first if it does not exist."""
    if not db_path.exists():
        build_database(db_path)
    return duckdb.connect(str(db_path), read_only=read_only)


if __name__ == "__main__":
    try:
        build_database()
    except FileNotFoundError as exc:
        print(exc)
        sys.exit(1)
