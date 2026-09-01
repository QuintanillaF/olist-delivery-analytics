"""Reproduce the whole analysis from a clean checkout.

    python -m venv .venv && .venv\\Scripts\\activate      (Windows)
    pip install -r requirements.txt
    python scripts/download_data.py        # needs Kaggle creds, or do it manually
    python run_all.py

Steps:
  1. build the DuckDB database from the raw CSVs (+ staging views)
  2. run every sql/*.sql analysis query, print a preview
  3. regenerate every figure in figures/
  4. execute notebooks/olist_analysis.ipynb end to end (if nbclient is present)
"""

from __future__ import annotations

import sys

from src import plots
from src.config import FIGURES_DIR, SQL_DIR
from src.db import build_database
from src.queries import list_queries, run_sql_file


def step_build() -> None:
    print("\n[1/4] Building database")
    build_database()


def step_run_queries() -> dict:
    print("\n[2/4] Running analysis queries")
    results = {}
    for name in list_queries():
        df = run_sql_file(name)
        results[name] = df
        print(f"  {name:<44} {len(df):>4} rows x {len(df.columns)} cols")
    return results


def step_figures(results: dict) -> None:
    print("\n[3/4] Rendering figures")
    plots.apply_style()
    r = results  # {query filename: DataFrame}

    plots.plot_q1_delivery_buckets(r["01_delivery_time_vs_review.sql"])
    plots.plot_q1_lateness(r["01_delivery_time_vs_review_by_lateness.sql"])
    plots.plot_q2_category_late(r["02_category_delivery_performance.sql"])

    repeat_rate = float(r["03_repeat_customers.sql"]["pct_ordering_2plus"].iloc[0])
    plots.plot_q3_repeat(r["03_repeat_customers_by_first_review.sql"], repeat_rate)

    plots.plot_q4_seller_segments(r["04_seller_segmentation.sql"])
    plots.plot_q5_seasonality(r["05_revenue_seasonality.sql"])
    plots.plot_q6_distance(
        r["06_geo_distance_vs_delay.sql"], r["06_geo_delay_by_state.sql"]
    )


def step_notebook() -> None:
    print("\n[4/4] Executing notebook")
    nb_path = SQL_DIR.parent / "notebooks" / "olist_analysis.ipynb"
    if not nb_path.exists():
        print("  (notebook not present yet - skipping)")
        return
    try:
        import nbformat
        from nbclient import NotebookClient
    except ImportError:
        print("  (nbclient not installed - skipping; pip install -r requirements.txt)")
        return
    nb = nbformat.read(nb_path, as_version=4)
    client = NotebookClient(
        nb, timeout=600, kernel_name="python3",
        resources={"metadata": {"path": str(nb_path.parent)}},
    )
    client.execute()
    nbformat.write(nb, nb_path)
    print(f"  executed {nb_path}")


def main() -> int:
    step_build()
    results = step_run_queries()
    step_figures(results)
    step_notebook()
    print(f"\nDone. Figures in {FIGURES_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
