# AI-assisted Hotel Booking Analytics

`app.py` is a Streamlit interface for the BI marts in SQL Server. It reads fixed, parameterized KPI queries from `bi.Fact_Hotel_Booking` and related dimensions, then sends only aggregated KPI values and monthly trends to Gemini. The model cannot create or execute SQL.

## Run

1. Install the root requirements and copy `.env.example` to `.env`.
2. Configure `HOTELBOOKING_SQLALCHEMY_URL`, `GEMINI_API_KEY`, and `GEMINI_MODEL`.
3. Run the Mage pipeline and dbt build once so the `bi` schema is populated.
4. Start the app from the repository root:

   ```bash
   streamlit run ai/app.py
   ```

Set `BI_SCHEMA=dw` to read the legacy SQL Server dimensional model instead of the dbt marts. The app separates `Canceled` from `No-Show` and labels `ADR × nights` for canceled/no-show records as estimated revenue at risk. Flagged ADR outliers are excluded from the at-risk estimate.
