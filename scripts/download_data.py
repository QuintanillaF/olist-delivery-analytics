"""Download the Olist Brazilian e-commerce dataset into data/raw/.

Two paths:

1. Kaggle API (automatic). Needs a Kaggle account and an API token:
       https://www.kaggle.com/settings/account  ->  "Create New Token"
   Put the downloaded kaggle.json at:
       Windows: %USERPROFILE%\\.kaggle\\kaggle.json
       macOS/Linux: ~/.kaggle/kaggle.json
   Then:  python scripts/download_data.py

2. Manual. If the API is not configured the script prints the exact steps
   and the list of files it expects.

Dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path

DATASET = "olistbr/brazilian-ecommerce"
RAW_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"

EXPECTED_FILES = [
    "olist_customers_dataset.csv",
    "olist_geolocation_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_orders_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]


def already_present() -> bool:
    return all((RAW_DIR / f).exists() for f in EXPECTED_FILES)


def manual_instructions() -> None:
    print(
        "\nCould not download automatically. Do it manually:\n"
        f"  1. Open https://www.kaggle.com/datasets/{DATASET}\n"
        "  2. Click 'Download' (needs a free Kaggle login).\n"
        f"  3. Unzip everything into: {RAW_DIR}\n\n"
        "Expected files:\n  " + "\n  ".join(EXPECTED_FILES) + "\n"
    )


def download_via_kaggle() -> bool:
    try:
        from kaggle.api.kaggle_api_extended import KaggleApi
    except (ImportError, OSError) as exc:
        # OSError: kaggle imports and immediately looks for credentials
        print(f"Kaggle API unavailable: {exc}")
        return False

    try:
        api = KaggleApi()
        api.authenticate()
        RAW_DIR.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {DATASET} -> {RAW_DIR}")
        api.dataset_download_files(DATASET, path=str(RAW_DIR), quiet=False)

        for zf in RAW_DIR.glob("*.zip"):
            with zipfile.ZipFile(zf) as z:
                z.extractall(RAW_DIR)
            zf.unlink()
        return already_present()
    except Exception as exc:  # noqa: BLE001 - report anything and fall back
        print(f"Kaggle download failed: {exc}")
        return False


def main() -> int:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    if already_present():
        print(f"All 9 files already in {RAW_DIR}. Nothing to do.")
        return 0

    if download_via_kaggle() and already_present():
        print(f"Done. Files in {RAW_DIR}.")
        return 0

    manual_instructions()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
