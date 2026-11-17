"""Build, test and export the star schema - the BI layer on top of staging.

Pipeline:
  1. ``build_star``  - execute ``sql/star/0*.sql`` in order: the state
                       reference view, the four dimensions, the fact table and
                       the flattened view.
  2. ``run_tests``   - execute ``sql/star/99_tests.sql``; every test must
                       report 0 failures.
  3. ``reconcile``   - re-run five of the analysis queries (``sql/01..05``) and
                       assert the star gives the same numbers, so the dashboard
                       and the README can never disagree.
  4. ``export_star`` - write the files a BI tool loads.

Nothing is exported unless every test passes.

    python -m src.star

Output, under ``data/bi/`` (git-ignored, like the rest of ``data/``):
    power_bi/*.parquet                    the five star tables, typed
    looker_studio/order_items_flat.csv    the star flattened into one table
    csv/*.csv                             the five star tables, for anything else

As everywhere in this project the SQL is never inlined: the model lives in
``sql/star/``. The only SQL in this file is the handful of one-line aggregates
that ``reconcile`` compares against the analysis queries.
"""

from __future__ import annotations

import sys
from pathlib import Path

import duckdb

from .config import DATA_DIR, DB_PATH, SQL_DIR
from .db import build_database

STAR_SQL_DIR = SQL_DIR / "star"
TESTS_FILE = "99_tests.sql"
BI_DIR = DATA_DIR / "bi"

# star table -> ORDER BY, so that an export is reproducible row for row
STAR_TABLES = {
    "dim_date": "date_key",
    "dim_customer": "customer_key",
    "dim_seller": "seller_key",
    "dim_product": "product_key",
    "fct_order_items": "order_id, order_item_id",
}
FLAT_VIEW = "order_items_flat"
FLAT_ORDER_BY = "order_id, order_item_id"

# Looker Studio's File Upload connector rejects data sets above 100 MB.
LOOKER_UPLOAD_LIMIT_MB = 100

# sql/04 names its segments in English; dim_seller stores the display label.
SEGMENT_LABELS = {
    "Core - invest": "Núcleo",
    "Rising - grow": "En ascenso",
    "Steady - maintain": "Estable",
    "At risk - fix or drop": "En riesgo",
}


# --------------------------------------------------------------------------- #
# 1. build
# --------------------------------------------------------------------------- #
def build_star(con: duckdb.DuckDBPyConnection) -> None:
    """Execute every sql/star/*.sql except the tests, in filename order."""
    files = sorted(p for p in STAR_SQL_DIR.glob("*.sql") if p.name != TESTS_FILE)
    if not files:
        raise FileNotFoundError(f"No star-schema SQL found in {STAR_SQL_DIR}")
    for path in files:
        con.execute(path.read_text(encoding="utf-8"))
    for table in STAR_TABLES:
        n = con.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
        print(f"  built {table:<18} {n:>8,} rows")


# --------------------------------------------------------------------------- #
# 2. tests
# --------------------------------------------------------------------------- #
def _report(ok: bool, label: str, detail: str = "") -> int:
    """Print one test line; return 1 if it failed (so callers can sum)."""
    print(f"  {'ok  ' if ok else 'FAIL'}  {label}" + (f"   [{detail}]" if detail and not ok else ""))
    return 0 if ok else 1


def run_tests(con: duckdb.DuckDBPyConnection) -> int:
    """Run sql/star/99_tests.sql. Returns the number of failed tests."""
    sql = (STAR_SQL_DIR / TESTS_FILE).read_text(encoding="utf-8")
    failed = 0
    for _, test, failures in con.execute(sql).fetchall():
        failed += _report(failures == 0, test, f"{failures} failures")
    return failed


# --------------------------------------------------------------------------- #
# 3. reconciliation with the analysis queries
# --------------------------------------------------------------------------- #
def _analysis(con: duckdb.DuckDBPyConnection, filename: str, columns: str,
              order_by: str = "") -> list[tuple]:
    """Run sql/<filename> as a sub-query and return the chosen columns."""
    sql = (SQL_DIR / filename).read_text(encoding="utf-8").strip().rstrip(";")
    tail = f" ORDER BY {order_by}" if order_by else ""
    return con.execute(f"SELECT {columns} FROM (\n{sql}\n) AS q{tail}").fetchall()


def _close(a: float, b: float, tol: float) -> bool:
    return a is not None and b is not None and abs(a - b) <= tol


def reconcile(con: duckdb.DuckDBPyConnection) -> int:
    """Assert the star reproduces the analysis queries. Returns failed count.

    Each analysis file rounds its output, so the tolerance of each comparison
    is half a unit of that rounding.
    """
    failed = 0

    # Q1 - orders and mean review per band of "days vs the promised date".
    # Exercises: is_delivered, the calendar-day lateness rule, the bucket
    # edges, review de-duplication and the order_weight average.
    want = _analysis(con, "01_delivery_time_vs_review_by_lateness.sql",
                     "orders, mean_review_score", "vs_promised_date")
    got = con.execute("""
        SELECT count(DISTINCT order_id),
               sum(review_score * order_weight) / sum(order_weight)
        FROM fct_order_items
        WHERE is_delivered = 1 AND review_score IS NOT NULL
        GROUP BY delivery_bucket_sort
        ORDER BY delivery_bucket_sort
    """).fetchall()
    ok = len(want) == len(got) and all(
        w[0] == g[0] and _close(w[1], g[1], 0.0005 + 1e-9) for w, g in zip(want, got)
    )
    failed += _report(ok, "agrees with sql/01: orders and mean review per lateness band",
                      f"analysis={want} star={got}")

    # Q2 - orders and late rate per category. Exercises: the lateness rule
    # (stg_orders.is_late) and dim_product, in a slice that splits orders.
    want = {cat: (orders, pct) for cat, orders, pct in
            _analysis(con, "02_category_delivery_performance.sql", "category, orders, pct_late")}
    got = {cat: (orders, pct) for cat, orders, pct in con.execute("""
        SELECT p.category,
               count(DISTINCT f.order_id),
               count(DISTINCT CASE WHEN f.is_late = 1 THEN f.order_id END)
                   / count(DISTINCT f.order_id)
        FROM fct_order_items AS f
        JOIN dim_product     AS p ON p.product_key = f.product_key
        WHERE f.is_delivered = 1 AND f.review_score IS NOT NULL
        GROUP BY p.category
        HAVING count(DISTINCT f.order_id) >= 200
    """).fetchall()}
    ok = want.keys() == got.keys() and all(
        want[c][0] == got[c][0] and _close(want[c][1], got[c][1], 0.0005 + 1e-9) for c in want
    )
    failed += _report(ok, "agrees with sql/02: orders and late rate per category",
                      f"analysis={want} star={got}")

    # Q3 - customers and repeat rate. Exercises: customer_unique_id as the
    # person, and the lifetime attributes of dim_customer.
    want = _analysis(con, "03_repeat_customers.sql", "customers, pct_ordering_2plus")
    got = con.execute("""
        SELECT count(DISTINCT customer_unique_id),
               count(DISTINCT customer_unique_id) FILTER (WHERE is_repeat_customer = 1)
                   / count(DISTINCT customer_unique_id)
        FROM dim_customer
        WHERE customer_lifetime_orders >= 1
    """).fetchall()
    ok = want[0][0] == got[0][0] and _close(want[0][1], got[0][1], 0.00005 + 1e-9)
    failed += _report(ok, "agrees with sql/03: customers and repeat-purchase rate",
                      f"analysis={want} star={got}")

    # Q4 - sellers and GMV per segment. Exercises: dim_seller.seller_segment.
    want = {SEGMENT_LABELS.get(seg, seg): (sellers, gmv) for seg, sellers, gmv in
            _analysis(con, "04_seller_segmentation.sql", "segment, sellers, gmv")}
    got = {seg: (sellers, gmv) for seg, sellers, gmv in con.execute("""
        SELECT seller_segment, count(*), round(sum(lifetime_gmv), 0)
        FROM dim_seller
        GROUP BY seller_segment
    """).fetchall()}
    ok = want.keys() == got.keys() and all(
        want[s][0] == got[s][0] and _close(want[s][1], got[s][1], 0.5) for s in want
    )
    failed += _report(ok, "agrees with sql/04: sellers and GMV per seller segment",
                      f"analysis={want} star={got}")

    # Q5 - orders and revenue per month, and which months are partial.
    # Exercises: item_total, is_canceled, the purchase-date role of dim_date
    # and dim_date.is_complete_month.
    want = _analysis(con, "05_revenue_seasonality.sql",
                     "month, orders, revenue, is_partial_month", "month")
    got = con.execute("""
        SELECT d.month_start, count(DISTINCT f.order_id),
               sum(f.item_total), min(d.is_complete_month)
        FROM fct_order_items AS f
        JOIN dim_date        AS d ON d.date_key = f.purchase_date_key
        WHERE f.is_canceled = 0
        GROUP BY d.month_start
        ORDER BY d.month_start
    """).fetchall()
    ok = len(want) == len(got) and all(
        w[0] == g[0] and w[1] == g[1] and _close(w[2], g[2], 0.005 + 1e-6)
        and bool(w[3]) == (g[3] == 0)
        for w, g in zip(want, got)
    )
    failed += _report(ok, "agrees with sql/05: orders, revenue and partial months, month by month",
                      f"analysis={want} star={got}")

    return failed


# --------------------------------------------------------------------------- #
# 4. export
# --------------------------------------------------------------------------- #
def _copy(con: duckdb.DuckDBPyConnection, query: str, path: Path, options: str) -> float:
    """COPY a query to a file. Returns the file size in MB."""
    target = path.as_posix().replace("'", "''")
    con.execute(f"COPY ({query}) TO '{target}' ({options})")
    size_mb = path.stat().st_size / 1e6
    print(f"  wrote {path.relative_to(DATA_DIR).as_posix():<44} {size_mb:>6.1f} MB")
    return size_mb


def export_star(con: duckdb.DuckDBPyConnection, out_dir: Path = BI_DIR) -> None:
    """Write the star for Power BI (Parquet), Looker Studio (one flat CSV) and
    as plain CSV.

    * Parquet keeps the column types, so Power BI cannot misread '129.90' as
      12990 on a machine whose regional settings use a decimal comma.
    * Looker Studio's File Upload connector only accepts CSV, and has no data
      model - hence a single flattened table.
    * CSV files are UTF-8, comma-separated, ISO dates, '.' as decimal point.
    """
    power_bi, looker, csv = out_dir / "power_bi", out_dir / "looker_studio", out_dir / "csv"
    for folder in (power_bi, looker, csv):
        folder.mkdir(parents=True, exist_ok=True)

    for table, order_by in STAR_TABLES.items():
        query = f"SELECT * FROM {table} ORDER BY {order_by}"
        _copy(con, query, power_bi / f"{table}.parquet", "FORMAT PARQUET")
        _copy(con, query, csv / f"{table}.csv", "FORMAT CSV, HEADER")

    flat_mb = _copy(con, f"SELECT * FROM {FLAT_VIEW} ORDER BY {FLAT_ORDER_BY}",
                    looker / f"{FLAT_VIEW}.csv", "FORMAT CSV, HEADER")
    if flat_mb > LOOKER_UPLOAD_LIMIT_MB:
        print(f"  WARNING: {FLAT_VIEW}.csv is over Looker Studio's "
              f"{LOOKER_UPLOAD_LIMIT_MB} MB upload limit - drop columns from "
              f"sql/star/06_order_items_flat.sql")


# --------------------------------------------------------------------------- #
# entry point
# --------------------------------------------------------------------------- #
def build_and_export(db_path: Path = DB_PATH) -> None:
    """Build the star in the database, test it, and export it."""
    if not db_path.exists():
        build_database(db_path)
    with duckdb.connect(str(db_path)) as con:
        build_star(con)
        failed = run_tests(con) + reconcile(con)
        if failed:
            raise RuntimeError(f"{failed} star-schema test(s) failed - nothing exported")
        export_star(con)


if __name__ == "__main__":
    try:
        build_and_export()
    except (FileNotFoundError, RuntimeError) as exc:
        print(exc)
        sys.exit(1)
