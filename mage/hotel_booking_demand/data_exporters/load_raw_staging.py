import os
import subprocess
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from mage_ai.data_preparation.decorators import data_exporter
from sqlalchemy import create_engine, text


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
load_dotenv(REPOSITORY_ROOT / ".env")
PACKAGE_NAME = "Mage_Hotel_Booking_Pipeline"


def _reset_full_load(connection) -> None:
    connection.execute(text("DELETE FROM dw.Fact_Daily_Stay_Snapshot"))
    connection.execute(text("DELETE FROM dw.Fact_Hotel_Booking"))
    connection.execute(text("DELETE FROM stg.hotel_bookings_clean"))
    connection.execute(text("DELETE FROM stg.hotel_bookings_error"))
    connection.execute(text("DELETE FROM stg.hotel_bookings_raw"))
    connection.execute(
        text(
            "UPDATE meta.etl_watermark "
            "SET last_watermark_value='1900-01-01', last_batch_id=NULL, "
            "updated_at=SYSDATETIME() WHERE entity_name='hotel_bookings'"
        )
    )


def _remove_failed_attempts(connection, source_file: str) -> None:
    """Remove partial output from prior failed runs so the same file can retry."""
    params = {"package_name": PACKAGE_NAME, "source_file": source_file}
    tables = (
        "dw.Fact_Daily_Stay_Snapshot",
        "dw.Fact_Hotel_Booking",
        "stg.hotel_bookings_clean",
        "stg.hotel_bookings_error",
        "stg.hotel_bookings_raw",
    )
    for table in tables:
        connection.execute(
            text(
                f"DELETE target FROM {table} AS target "
                "INNER JOIN meta.etl_batch_log AS log ON log.batch_id=target.batch_id "
                "WHERE log.package_name=:package_name AND log.source_file=:source_file "
                "AND log.status IN ('FAILED', 'RUNNING')"
            ),
            params,
        )

    connection.execute(
        text(
            "UPDATE meta.etl_watermark "
            "SET last_watermark_value=COALESCE(("
            "  SELECT CONVERT(nvarchar(100), MAX(arrival_date), 23) "
            "  FROM stg.hotel_bookings_clean"
            "), '1900-01-01'), last_batch_id=NULL, updated_at=SYSDATETIME() "
            "WHERE entity_name='hotel_bookings'"
        )
    )


@data_exporter
def load_raw_staging_and_build_marts(df: pd.DataFrame, *args, **kwargs) -> None:
    """Load a CSV batch, validate/load the SQL DDS, then build dbt BI models."""
    connection_url = os.getenv("HOTELBOOKING_SQLALCHEMY_URL")
    if not connection_url:
        raise RuntimeError("Set HOTELBOOKING_SQLALCHEMY_URL in the environment or .env.")

    configured_path = kwargs.get("source_file") or os.getenv(
        "HOTEL_BOOKINGS_CSV", "data/raw/hotel_bookings.csv"
    )
    source_path = Path(configured_path)
    if not source_path.is_absolute():
        source_path = REPOSITORY_ROOT / source_path
    source_file = str(source_path.expanduser().resolve())
    load_type = str(
        kwargs.get("load_type") or os.getenv("HOTEL_BOOKINGS_LOAD_TYPE", "FULL")
    ).strip().upper()
    if load_type not in {"FULL", "INCREMENTAL"}:
        raise ValueError("HOTEL_BOOKINGS_LOAD_TYPE must be FULL or INCREMENTAL.")

    engine = create_engine(connection_url, pool_pre_ping=True, fast_executemany=True)
    batch_id = None
    try:
        with engine.begin() as connection:
            if load_type == "INCREMENTAL":
                already_loaded = connection.execute(
                    text(
                        "SELECT COUNT_BIG(*) FROM meta.etl_batch_log "
                        "WHERE package_name=:package_name AND source_file=:source_file "
                        "AND status='SUCCESS'"
                    ),
                    {"package_name": PACKAGE_NAME, "source_file": source_file},
                ).scalar_one()
                if already_loaded:
                    raise ValueError(
                        "This incremental source file already completed successfully. "
                        "Choose a new batch file or use FULL for a rebuild."
                    )
                _remove_failed_attempts(connection, source_file)
            else:
                _reset_full_load(connection)

            batch_id = connection.execute(
                text(
                    "INSERT INTO meta.etl_batch_log "
                    "(package_name, load_type, source_file, status) "
                    "OUTPUT inserted.batch_id "
                    "VALUES (:package_name, :load_type, :source_file, 'RUNNING')"
                ),
                {
                    "package_name": PACKAGE_NAME,
                    "load_type": load_type,
                    "source_file": source_file,
                },
            ).scalar_one()

        raw_rows = df.copy()
        raw_rows.insert(0, "batch_id", int(batch_id))
        raw_rows.insert(1, "source_file_name", Path(source_file).name)
        with engine.begin() as connection:
            raw_rows.to_sql(
                "hotel_bookings_raw",
                con=connection,
                schema="stg",
                if_exists="append",
                index=False,
                chunksize=2000,
                method=None,
            )

        with engine.begin() as connection:
            connection.execute(
                text("EXEC stg.sp_clean_and_validate_staging @BatchId=:batch_id"),
                {"batch_id": int(batch_id)},
            )
            connection.execute(
                text("EXEC dw.sp_load_dds_from_staging @BatchId=:batch_id"),
                {"batch_id": int(batch_id)},
            )

        dbt_executable = os.getenv("DBT_EXECUTABLE")
        if not dbt_executable:
            candidates = (
                REPOSITORY_ROOT / ".venv-dbt" / "bin" / "dbt",
                REPOSITORY_ROOT / ".venv-dbt" / "Scripts" / "dbt.exe",
            )
            dbt_executable = next(
                (str(candidate) for candidate in candidates if candidate.is_file()),
                "dbt",
            )
        dbt_command = [
            dbt_executable,
            "build",
            "--project-dir",
            str(REPOSITORY_ROOT / "dbt"),
            "--profiles-dir",
            str(REPOSITORY_ROOT / "dbt"),
            "--target",
            os.getenv("DBT_TARGET", "dev"),
            "--no-use-colors",
        ]
        subprocess.run(dbt_command, cwd=REPOSITORY_ROOT, check=True)

        with engine.begin() as connection:
            rows_rejected = connection.execute(
                text(
                    "SELECT COUNT_BIG(*) FROM stg.hotel_bookings_error "
                    "WHERE batch_id=:batch_id"
                ),
                {"batch_id": int(batch_id)},
            ).scalar_one()
            rows_inserted = connection.execute(
                text(
                    "SELECT (SELECT COUNT_BIG(*) FROM dw.Fact_Hotel_Booking "
                    "WHERE batch_id=:batch_id) + "
                    "(SELECT COUNT_BIG(*) FROM dw.Fact_Daily_Stay_Snapshot "
                    "WHERE batch_id=:batch_id)"
                ),
                {"batch_id": int(batch_id)},
            ).scalar_one()
            connection.execute(
                text(
                    "UPDATE meta.etl_batch_log SET end_time=SYSDATETIME(), "
                    "status='SUCCESS', rows_extracted=:rows_extracted, "
                    "rows_inserted=:rows_inserted, rows_rejected=:rows_rejected "
                    "WHERE batch_id=:batch_id"
                ),
                {
                    "batch_id": int(batch_id),
                    "rows_extracted": len(df),
                    "rows_inserted": int(rows_inserted),
                    "rows_rejected": int(rows_rejected),
                },
            )
    except Exception as error:
        if batch_id is not None:
            with engine.begin() as connection:
                connection.execute(
                    text(
                        "UPDATE meta.etl_batch_log SET end_time=SYSDATETIME(), "
                        "status='FAILED', error_message=:error_message "
                        "WHERE batch_id=:batch_id"
                    ),
                    {
                        "batch_id": int(batch_id),
                        "error_message": str(error)[:4000],
                    },
                )
        raise
    finally:
        engine.dispose()
