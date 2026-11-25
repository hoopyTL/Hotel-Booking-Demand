import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from mage_ai.data_preparation.decorators import data_loader


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
load_dotenv(REPOSITORY_ROOT / ".env")


@data_loader
def load_source_csv(*args, **kwargs) -> pd.DataFrame:
    """Read the Kaggle CSV as strings so NA/NULL tokens survive into staging."""
    configured_path = kwargs.get("source_file") or os.getenv(
        "HOTEL_BOOKINGS_CSV", "data/raw/hotel_bookings.csv"
    )
    source_path = Path(configured_path)
    if not source_path.is_absolute():
        source_path = REPOSITORY_ROOT / source_path
    source_path = source_path.expanduser().resolve()

    if not source_path.is_file():
        raise FileNotFoundError(
            f"Hotel Booking Demand CSV not found: {source_path}. "
            "Set HOTEL_BOOKINGS_CSV or place the file in data/raw/."
        )

    return pd.read_csv(
        source_path,
        dtype=str,
        keep_default_na=False,
        encoding="utf-8-sig",
        low_memory=False,
    )
