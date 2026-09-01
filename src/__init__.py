"""Olist e-commerce analysis - Python orchestration layer.

All data work lives in ``sql/``. This package only:
  * builds the DuckDB database from the raw CSVs (``db``),
  * runs a ``.sql`` file and hands back a DataFrame (``queries``),
  * draws the charts (``plots``).
"""
