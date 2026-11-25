import json
import os
from typing import Any

import pandas as pd
import streamlit as st
from dotenv import load_dotenv
from google import genai
from google.genai import types
from sqlalchemy import create_engine, text


load_dotenv()


def _bi_schema() -> str:
    schema = os.getenv("BI_SCHEMA", "bi").strip()
    if schema not in {"bi", "dw"}:
        raise ValueError("BI_SCHEMA must be either 'bi' or 'dw'.")
    return schema


def _engine():
    url = os.getenv("HOTELBOOKING_SQLALCHEMY_URL")
    if not url:
        raise RuntimeError("Set HOTELBOOKING_SQLALCHEMY_URL in .env.")
    return create_engine(url, pool_pre_ping=True)


def _read_frame(engine, query: str, params: dict[str, Any] | None = None) -> pd.DataFrame:
    return pd.read_sql_query(text(query), engine, params=params or {})


def _filter_options(engine, schema: str) -> tuple[list[int], list[str]]:
    years = _read_frame(
        engine,
        f"SELECT DISTINCT arrival_date.[year] "
        f"FROM [{schema}].[Fact_Hotel_Booking] AS booking "
        f"INNER JOIN [{schema}].[Dim_Date] AS arrival_date "
        "ON arrival_date.date_key=booking.arrival_date_key "
        "ORDER BY arrival_date.[year]",
    )["year"].astype(int).tolist()
    hotels = _read_frame(
        engine,
        f"SELECT DISTINCT hotel_name FROM [{schema}].[Dim_Hotel] ORDER BY hotel_name",
    )["hotel_name"].astype(str).tolist()
    return years, hotels


def _load_kpis(engine, schema: str, year: int, hotel: str | None) -> pd.DataFrame:
    query = f"""
        SELECT
            COUNT_BIG(*) AS total_bookings,
            SUM(CASE WHEN status.reservation_status='Check-Out' THEN 1 ELSE 0 END) AS completed_bookings,
            SUM(CASE WHEN status.reservation_status='Canceled' THEN 1 ELSE 0 END) AS canceled_bookings,
            SUM(CASE WHEN status.reservation_status='No-Show' THEN 1 ELSE 0 END) AS no_show_bookings,
            SUM(CASE WHEN status.reservation_status='Check-Out' THEN booking.actual_revenue ELSE 0 END) AS actual_revenue,
            SUM(CASE WHEN status.is_canceled=1 AND booking.is_adr_outlier=0 THEN booking.lost_revenue ELSE 0 END) AS estimated_revenue_at_risk,
            SUM(CASE WHEN status.reservation_status='Check-Out' THEN booking.total_nights ELSE 0 END) AS room_nights_sold,
            SUM(CASE WHEN status.reservation_status='Check-Out' AND booking.is_adr_outlier=0 THEN booking.actual_revenue ELSE 0 END) AS valid_actual_revenue,
            SUM(CASE WHEN status.reservation_status='Check-Out' AND booking.is_adr_outlier=0 THEN booking.total_nights ELSE 0 END) AS valid_room_nights,
            SUM(CASE WHEN booking.is_room_changed=1 THEN 1 ELSE 0 END) AS room_changes
        FROM [{schema}].[Fact_Hotel_Booking] AS booking
        INNER JOIN [{schema}].[Dim_Reservation_Status] AS status
            ON status.reservation_status_key=booking.reservation_status_key
        INNER JOIN [{schema}].[Dim_Date] AS arrival_date
            ON arrival_date.date_key=booking.arrival_date_key
        INNER JOIN [{schema}].[Dim_Hotel] AS hotel
            ON hotel.hotel_key=booking.hotel_key
        WHERE arrival_date.[year]=:year
          AND (:hotel IS NULL OR hotel.hotel_name=:hotel)
    """
    return _read_frame(engine, query, {"year": year, "hotel": hotel})


def _load_monthly(engine, schema: str, year: int, hotel: str | None) -> pd.DataFrame:
    query = f"""
        SELECT
            arrival_date.month_number,
            arrival_date.month_name,
            COUNT_BIG(*) AS total_bookings,
            SUM(CASE WHEN status.reservation_status='Canceled' THEN 1 ELSE 0 END) AS canceled_bookings,
            SUM(CASE WHEN status.reservation_status='No-Show' THEN 1 ELSE 0 END) AS no_show_bookings,
            SUM(CASE WHEN status.reservation_status='Check-Out' THEN booking.actual_revenue ELSE 0 END) AS actual_revenue
        FROM [{schema}].[Fact_Hotel_Booking] AS booking
        INNER JOIN [{schema}].[Dim_Reservation_Status] AS status
            ON status.reservation_status_key=booking.reservation_status_key
        INNER JOIN [{schema}].[Dim_Date] AS arrival_date
            ON arrival_date.date_key=booking.arrival_date_key
        INNER JOIN [{schema}].[Dim_Hotel] AS hotel
            ON hotel.hotel_key=booking.hotel_key
        WHERE arrival_date.[year]=:year
          AND (:hotel IS NULL OR hotel.hotel_name=:hotel)
        GROUP BY arrival_date.month_number, arrival_date.month_name
        ORDER BY arrival_date.month_number
    """
    return _read_frame(engine, query, {"year": year, "hotel": hotel})


def _generate_insight(question: str, context: dict[str, Any]) -> str:
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("Set GEMINI_API_KEY in .env to enable AI insights.")

    model = os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
    prompt = (
        "Dữ liệu KPI dưới đây được truy vấn trực tiếp từ data warehouse. "
        "Trả lời bằng tiếng Việt, chỉ nêu điều được số liệu hỗ trợ, trích số liệu cụ thể, "
        "phân biệt tương quan với nguyên nhân, và nói rõ nếu dữ liệu không đủ để kết luận.\n\n"
        f"KPI_CONTEXT_JSON:\n{json.dumps(context, ensure_ascii=False, default=str)}\n\n"
        f"Câu hỏi: {question}"
    )
    with genai.Client(api_key=api_key) as client:
        response = client.models.generate_content(
            model=model,
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0.2,
                max_output_tokens=900,
                system_instruction=(
                    "You are a careful hotel BI analyst. Use only the provided KPI context. "
                    "Never invent data, causes, or recommendations that are not supported."
                ),
            ),
        )
    return response.text or "Mô hình không trả về nội dung."


st.set_page_config(page_title="Hotel Booking BI + AI", page_icon="🏨", layout="wide")
st.title("Hotel Booking Demand — BI & AI Insights")
st.caption("Số liệu được truy vấn từ SQL Server; Gemini chỉ nhận KPI tổng hợp, không nhận dữ liệu booking thô.")

try:
    schema = _bi_schema()
    engine = _engine()
    years, hotels = _filter_options(engine, schema)
except Exception as error:
    st.error(f"Chưa kết nối được BI mart: {error}")
    st.info("Chạy SQL setup, pipeline Mage/dbt và cấu hình HOTELBOOKING_SQLALCHEMY_URL trong .env trước.")
    st.stop()

if not years or not hotels:
    st.warning("Data warehouse chưa có dimension để phân tích. Hãy nạp dữ liệu rồi mở lại ứng dụng.")
    st.stop()

filter_col1, filter_col2 = st.columns(2)
selected_year = filter_col1.selectbox("Năm nhận phòng", years, index=len(years) - 1)
selected_hotel = filter_col2.selectbox("Khách sạn", ["All hotels", *hotels])
hotel_filter = None if selected_hotel == "All hotels" else selected_hotel

try:
    kpi_frame = _load_kpis(engine, schema, selected_year, hotel_filter)
    monthly = _load_monthly(engine, schema, selected_year, hotel_filter)
except Exception as error:
    st.error(f"Không đọc được KPI từ schema [{schema}]: {error}")
    st.stop()
finally:
    engine.dispose()

if kpi_frame.empty or int(kpi_frame.loc[0, "total_bookings"] or 0) == 0:
    st.info("Không có booking phù hợp với bộ lọc hiện tại.")
    st.stop()

kpi = kpi_frame.iloc[0]
total = int(kpi["total_bookings"] or 0)
canceled = int(kpi["canceled_bookings"] or 0)
no_show = int(kpi["no_show_bookings"] or 0)
completed = int(kpi["completed_bookings"] or 0)
actual_revenue = float(kpi["actual_revenue"] or 0)
revenue_at_risk = float(kpi["estimated_revenue_at_risk"] or 0)
room_nights = int(kpi["room_nights_sold"] or 0)
valid_room_nights = int(kpi["valid_room_nights"] or 0)
valid_revenue = float(kpi["valid_actual_revenue"] or 0)

cards = st.columns(5)
cards[0].metric("Bookings", f"{total:,}")
cards[1].metric("Canceled", f"{canceled:,}", f"{canceled / total:.1%}")
cards[2].metric("No-show", f"{no_show:,}", f"{no_show / total:.1%}")
cards[3].metric("Actual revenue", f"€{actual_revenue:,.0f}")
cards[4].metric("Revenue at risk*", f"€{revenue_at_risk:,.0f}")

left, right = st.columns([1, 1])
with left:
    st.subheader("Booking outcomes by arrival month")
    if not monthly.empty:
        trend = monthly.set_index("month_name")[["canceled_bookings", "no_show_bookings"]]
        trend.columns = ["Canceled", "No-show"]
        st.bar_chart(trend)
    else:
        st.info("Không có dữ liệu theo tháng cho bộ lọc này.")
with right:
    st.subheader("Operational and pricing KPIs")
    st.write(f"Completed bookings: **{completed:,}**")
    st.write(f"Room nights sold: **{room_nights:,}**")
    weighted_adr = valid_revenue / valid_room_nights if valid_room_nights else 0
    st.write(f"Weighted ADR (excluding flagged outliers): **€{weighted_adr:,.2f}**")
    st.write(f"Bookings with room changes: **{int(kpi['room_changes'] or 0):,}**")
    st.caption("*Revenue at risk = ADR × nights for Canceled/No-Show records; flagged ADR outliers are excluded. This is an estimate, not observed lost revenue.")

st.subheader("Ask for a grounded explanation")
question = st.text_input(
    "Câu hỏi",
    value="Hãy tóm tắt kết quả năm này và chỉ ra biến động đáng chú ý theo tháng.",
)
if st.button("Generate AI insight", type="primary"):
    context = {
        "filters": {"arrival_year": selected_year, "hotel": selected_hotel},
        "kpis": {
            "total_bookings": total,
            "completed_bookings": completed,
            "canceled_bookings": canceled,
            "canceled_rate": canceled / total,
            "no_show_bookings": no_show,
            "no_show_rate": no_show / total,
            "actual_revenue_eur": actual_revenue,
            "estimated_revenue_at_risk_eur": revenue_at_risk,
            "room_nights_sold": room_nights,
            "weighted_adr_eur": weighted_adr,
            "room_change_bookings": int(kpi["room_changes"] or 0),
        },
        "monthly_trend": monthly.to_dict(orient="records"),
    }
    try:
        st.markdown(_generate_insight(question, context))
    except Exception as error:
        st.error(f"Không tạo được AI insight: {error}")
