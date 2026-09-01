"""Shared configuration: paths and the chart palette.

The palette is a validated, brand-neutral default (OKLab-checked for
colour-vision-deficiency separation and contrast on a light surface). Rules we
follow so the charts read as one system:

  * categorical hues are used in the fixed order below, never cycled;
  * scatter / bubble charts use at most the first THREE categorical hues
    (the all-pairs separation guarantee stops there) - beyond that, encode
    with position + a single highlight colour against grey;
  * magnitude -> the sequential blue ramp (light = low, dark = high);
  * a signed quantity (early vs late) -> the diverging blue<->red pair with a
    grey midpoint;
  * text stays in ink colours, never a series colour.
"""

from __future__ import annotations

from pathlib import Path

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql"
DATA_DIR = ROOT / "data"
RAW_DIR = DATA_DIR / "raw"
FIGURES_DIR = ROOT / "figures"
DB_PATH = DATA_DIR / "olist.duckdb"

# The 9 raw CSVs -> table names (names kept verbatim so SQL matches Kaggle docs)
RAW_TABLES = {
    "olist_customers_dataset": "olist_customers_dataset.csv",
    "olist_geolocation_dataset": "olist_geolocation_dataset.csv",
    "olist_order_items_dataset": "olist_order_items_dataset.csv",
    "olist_order_payments_dataset": "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset": "olist_order_reviews_dataset.csv",
    "olist_orders_dataset": "olist_orders_dataset.csv",
    "olist_products_dataset": "olist_products_dataset.csv",
    "olist_sellers_dataset": "olist_sellers_dataset.csv",
    "product_category_name_translation": "product_category_name_translation.csv",
}

# --------------------------------------------------------------------------- #
# Palette
# --------------------------------------------------------------------------- #
SURFACE = "#fcfcfb"

INK = {
    "primary": "#0b0b0b",
    "secondary": "#52514e",
    "muted": "#898781",     # axis labels, ticks
    "grid": "#e1e0d9",      # hairline gridlines
    "baseline": "#c3c2b7",  # axis spines
}

# Fixed categorical order - index 0 first, never re-shuffled.
CATEGORICAL = [
    "#2a78d6",  # blue
    "#eb6834",  # orange
    "#1baf7a",  # aqua
    "#eda100",  # yellow
    "#e87ba4",  # magenta
    "#008300",  # green
]

PRIMARY = CATEGORICAL[0]  # default single-series colour (not matplotlib blue)

# Sequential blue ramp, light -> dark (magnitude encoding)
SEQUENTIAL = [
    "#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5",
    "#256abf", "#184f95", "#0d366b",
]

# Diverging blue <-> red, grey midpoint (signed quantity: early vs late)
DIVERGING = {"low": "#2a78d6", "mid": "#f0efec", "high": "#e34948"}

# Reserved status colours - state, never "series 4". Always with a label.
STATUS = {
    "good": "#0ca30c",
    "warning": "#fab219",
    "serious": "#ec835a",
    "critical": "#d03b3b",
}
