import pandas as pd
from mage_ai.data_preparation.decorators import transformer


EXPECTED_COLUMNS = [
    "hotel",
    "is_canceled",
    "lead_time",
    "arrival_date_year",
    "arrival_date_month",
    "arrival_date_week_number",
    "arrival_date_day_of_month",
    "stays_in_weekend_nights",
    "stays_in_week_nights",
    "adults",
    "children",
    "babies",
    "meal",
    "country",
    "market_segment",
    "distribution_channel",
    "is_repeated_guest",
    "previous_cancellations",
    "previous_bookings_not_canceled",
    "reserved_room_type",
    "assigned_room_type",
    "booking_changes",
    "deposit_type",
    "agent",
    "company",
    "days_in_waiting_list",
    "customer_type",
    "adr",
    "required_car_parking_spaces",
    "total_of_special_requests",
    "reservation_status",
    "reservation_status_date",
]


@transformer
def validate_source(df: pd.DataFrame, *args, **kwargs) -> pd.DataFrame:
    """Fail early on schema drift or missing core values; preserve source rows."""
    if not isinstance(df, pd.DataFrame):
        raise TypeError("Expected a pandas DataFrame from the CSV loader.")
    if df.empty:
        raise ValueError("The source CSV has a header but no booking rows.")

    missing = sorted(set(EXPECTED_COLUMNS) - set(df.columns))
    extra = sorted(set(df.columns) - set(EXPECTED_COLUMNS))
    if missing or extra:
        raise ValueError(
            f"Unexpected source schema. Missing columns: {missing}; extra columns: {extra}."
        )

    df = df.loc[:, EXPECTED_COLUMNS].copy()
    required = [
        "hotel",
        "arrival_date_year",
        "arrival_date_month",
        "arrival_date_day_of_month",
        "adr",
        "reservation_status",
        "reservation_status_date",
    ]
    blank_counts = {
        column: int(df[column].astype(str).str.strip().eq("").sum())
        for column in required
    }
    blank_counts = {column: count for column, count in blank_counts.items() if count}
    if blank_counts:
        raise ValueError(f"Required source fields contain blanks: {blank_counts}.")

    return df
