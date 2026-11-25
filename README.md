# Hotel Booking Demand: Business Intelligence and AI Mini Project

An end-to-end Business Intelligence project based on the [Hotel Booking Demand dataset](https://www.kaggle.com/datasets/jessemostipak/hotel-booking-demand). It prepares a SQL Server data warehouse, an orchestrated ingestion pipeline, dbt BI models and data tests, Power BI design materials, and a Streamlit application that generates evidence-based summaries with Gemini.

## Architecture

```text
Kaggle CSV
   │
   ▼
Mage.ai: load, validate, and orchestrate full/incremental batches
   │
   ▼
SQL Server: raw staging → SQL validation and DDS dimensions/facts
   │
   ▼
dbt: BI views, fact tables, and data quality tests
   ├── Power BI semantic model and dashboards
   └── Streamlit + Gemini KPI summaries
```

The current pipeline uses SQL Server stored procedures to clean staging data and load the core `dw` dimensional model. dbt builds and tests the BI-facing models in the `bi` schema. SSIS materials are retained as an alternative implementation; Mage is the primary ingestion workflow.

## Repository layout

| Path | Contents |
|---|---|
| `mage/hotel_booking_demand/` | Mage pipeline for CSV ingestion, source validation, batch logging, SQL procedure calls, and dbt orchestration |
| `sql/` | SQL Server database setup, metadata and staging tables, dimensional warehouse DDL, and stored procedures |
| `dbt/` | BI models, source/model documentation, SQL Server profile, and data tests |
| `bi/` | DAX measure definitions, dashboard specification, and Power BI theme |
| `ai/` | Streamlit application for KPI exploration and Gemini-generated explanations |
| `docs/` | Project brief and discovery/data-modeling documentation |
| `scripts/` | Dataset profiling and full/incremental batch preparation utilities |
| `ssis/` | SSIS alternative workflow documentation and packages |

## Prerequisites

- Python 3.10 or later
- SQL Server 2017 or later and Microsoft ODBC Driver 18 for SQL Server
- Power BI Desktop to build and save the `.pbix` deliverable
- A Gemini API key to use AI-generated insights
- The Kaggle CSV, which is not included in this repository

## Setup

1. Download `hotel_bookings.csv` from the [Kaggle dataset page](https://www.kaggle.com/datasets/jessemostipak/hotel-booking-demand) and place it at `data/raw/hotel_bookings.csv`.

2. Create a local environment file and configure the SQL Server connection and credentials:

   ```bash
   cp .env.example .env
   ```

   URL-encode special characters in credentials used by `HOTELBOOKING_SQLALCHEMY_URL`. Set `DBT_TRUST_CERT=true` only when connecting to a local SQL Server with a self-signed certificate. Keep `.env` private; it is excluded from Git.

3. In SQL Server Management Studio, run these scripts in order, then populate the date dimension:

   ```text
   sql/ddl/01_init_databases_and_schemas.sql
   sql/ddl/02_ddl_metadata.sql
   sql/ddl/03_ddl_staging.sql
   sql/ddl/04_ddl_dds_dw.sql
   sql/procedures/05_sp_etl_helpers.sql
   ```

   ```sql
   EXEC dw.sp_populate_dim_date;
   ```

4. Create the Python environments and install dependencies:

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   pip install -r mage/hotel_booking_demand/requirements.txt

   python3 -m venv .venv-dbt
   .venv-dbt/bin/pip install -r dbt/requirements.txt
   ```

   On Windows, use `.venv-dbt\Scripts\pip.exe` and `.venv-dbt\Scripts\dbt.exe`. Mage discovers dbt in the local environment by default; set `DBT_EXECUTABLE` in `.env` if it is installed elsewhere. The SQL Server account needs permission to create or replace objects in the `bi` schema.

## Run the ingestion pipeline

From the repository root, profile the source and create the sample full and incremental batches:

```bash
source .venv/bin/activate
python scripts/data_profiling.py --input data/raw/hotel_bookings.csv
python scripts/split_incremental_batches.py --input data/raw/hotel_bookings.csv --out-dir data/batches
```

Start Mage from the `mage/` directory:

```bash
cd mage
mage start hotel_booking_demand
```

Run the `hotel_booking_etl` pipeline with the following source-file and load-type pairs:

| Run | `source_file` | `load_type` |
|---|---|---|
| Initial load | `data/batches/batch_01_initial_2015_2016.csv` | `FULL` |
| Incremental load | `data/batches/batch_02_incremental_2017.csv` | `INCREMENTAL` |

The pipeline writes raw rows to staging, calls `stg.sp_clean_and_validate_staging` and `dw.sp_load_dds_from_staging`, and then runs `dbt build`. Batch status, processed/rejected row counts, and errors are recorded in SQL Server metadata tables. A successful incremental source file cannot be loaded twice; failed batches can be retried.

The same defaults can be configured with `HOTEL_BOOKINGS_CSV` and `HOTEL_BOOKINGS_LOAD_TYPE` in `.env`. In the Mage UI, run variables can override those defaults.

## Run dbt separately

After the warehouse has been initialized and populated, load `.env` into the shell and run dbt from the repository root:

```bash
set -a
source .env
set +a

.venv-dbt/bin/dbt debug --project-dir dbt --profiles-dir dbt
.venv-dbt/bin/dbt build --project-dir dbt --profiles-dir dbt
.venv-dbt/bin/dbt docs generate --project-dir dbt --profiles-dir dbt
```

The dbt project exposes warehouse dimensions as views in `HotelBooking_DW.bi` and builds booking-level and nightly-stay fact tables there. The booking fact has one row per accepted source booking; the nightly fact has one row per occupied night for completed bookings with at least one night.

## Power BI and AI

Connect Power BI to the SQL Server `bi` schema and use the model relationships and two-page dashboard design in [`bi/dashboard_spec.md`](bi/dashboard_spec.md). DAX measures are documented in [`bi/dax_measures.md`](bi/dax_measures.md). Keep booking-level measures on `Fact_Hotel_Booking` and nightly occupancy/revenue measures on `Fact_Daily_Stay_Snapshot` to avoid multiplying booking amounts by stay length.

Once the `bi` schema is populated and `.env` contains `HOTELBOOKING_SQLALCHEMY_URL` and `GEMINI_API_KEY`, launch the Streamlit app:

```bash
source .venv/bin/activate
streamlit run ai/app.py
```

The app runs fixed, parameterized queries against the warehouse and sends aggregated KPIs and monthly trends to Gemini. It does not generate SQL from user questions or send raw booking rows. Configure `GEMINI_MODEL` to select the model used by the Google Gen AI SDK.

## Submission readiness

The repository contains the source code and implementation materials for ingestion, warehouse setup, dbt models/tests, Power BI design, and AI-assisted analysis. The final submission still requires a successful run against the actual dataset and SQL Server, the finished Power BI `.pbix`, a results-based project report in PDF, and a demo video. These deliverables should reflect verified outputs from the completed run.
