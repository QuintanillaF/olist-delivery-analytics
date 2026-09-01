"""Run a ``.sql`` file against the built database and return a DataFrame.

This is the whole bridge between SQL and Python. The SQL is never inlined in
Python - it lives in ``sql/*.sql`` where a recruiter can read it. Here we only
load the file, send it to DuckDB, and hand back the result.
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from .config import SQL_DIR
from .db import get_connection

# Files that define views / do setup rather than return an analysis result.
_NON_QUERY_FILES = {"00_staging.sql"}


def run_sql_file(name: str) -> pd.DataFrame:
    """Execute ``sql/<name>`` (``.sql`` optional) and return the result.

    The staging views are guaranteed to exist (get_connection builds the
    database on first use).
    """
    filename = name if name.endswith(".sql") else f"{name}.sql"
    path = SQL_DIR / filename
    if not path.exists():
        raise FileNotFoundError(f"No such SQL file: {path}")
    if filename in _NON_QUERY_FILES:
        raise ValueError(f"{filename} is a setup script, not a query")

    sql = path.read_text(encoding="utf-8")
    with get_connection() as con:
        return con.execute(sql).df()


def sql_text(name: str) -> str:
    """The raw text of a ``sql/`` file - for showing the query in the notebook
    next to its result."""
    filename = name if name.endswith(".sql") else f"{name}.sql"
    return (SQL_DIR / filename).read_text(encoding="utf-8")


def list_queries() -> list[str]:
    """Every analysis query file, in numeric order."""
    return sorted(
        p.name
        for p in SQL_DIR.glob("*.sql")
        if p.name not in _NON_QUERY_FILES
    )


if __name__ == "__main__":
    for q in list_queries():
        df = run_sql_file(q)
        print(f"\n=== {q}  ({len(df)} rows) ===")
        print(df.to_string(index=False))
