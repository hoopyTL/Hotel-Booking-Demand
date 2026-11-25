# Power BI Dashboard Specification

Import the dbt models from SQL Server schema `bi`. The model names below are the SQL table/view aliases created by dbt.

## Semantic model

Create one-to-many, single-direction relationships from each dimension to its fact:

| Dimension | Key | Fact column | Fact table |
|---|---|---|---|
| `Dim_Date` | `date_key` | `arrival_date_key` | `Fact_Hotel_Booking` |
| `Dim_Hotel` | `hotel_key` | `hotel_key` | Both facts |
| `Dim_Country` | `country_key` | `country_key` | `Fact_Hotel_Booking` |
| `Dim_Market_Segment` | `market_segment_key` | `market_segment_key` | Both facts |
| `Dim_Distribution_Channel` | `distribution_channel_key` | `distribution_channel_key` | `Fact_Hotel_Booking` |
| `Dim_Room_Type` | `room_type_key` | `reserved_room_type_key`, `assigned_room_type_key` | `Fact_Hotel_Booking` |
| `Dim_Booking_Profile` | `booking_profile_key` | `booking_profile_key` | Both facts |
| `Dim_Reservation_Status` | `reservation_status_key` | `reservation_status_key` | `Fact_Hotel_Booking` |
| `Dim_Agent_Company` | `agent_company_key` | `agent_company_key` | `Fact_Hotel_Booking` |
| `Dim_Date` | `date_key` | `stay_date_key` | `Fact_Daily_Stay_Snapshot` |

Keep the arrival-date relationship active. For booking date and status date analysis, create role-playing copies of `Dim_Date` or use inactive relationships with `USERELATIONSHIP`. Do the same for reserved versus assigned room type. Use `Fact_Hotel_Booking` for booking counts and guest/booking measures; use `Fact_Daily_Stay_Snapshot` for nightly occupancy and allocated revenue so booking-level amounts are not multiplied by stay length.

## Page 1 — Overview

- KPI cards: Total Bookings, Cancellation Rate, No-Show Rate, Actual Revenue, Estimated Revenue At Risk, Weighted ADR.
- Monthly line chart: bookings, completed bookings, and Canceled/No-Show rates by arrival month.
- Stacked column: completed / Canceled / No-Show bookings by hotel.
- Line or area chart: room nights and allocated revenue by stay date, from the nightly fact.
- Slicers: arrival year/month, hotel, market segment, distribution channel.

## Page 2 — Cancellation and Operations Diagnostic

- Bar chart: Canceled and No-Show rates by deposit type, market segment, distribution channel, and hotel.
- Lead-time analysis: booking volume and cancellation rate by lead-time bands (0–7, 8–30, 31–90, 91–180, 181+ days).
- Detail matrix: hotel, arrival month, segment, deposit type, total bookings, canceled bookings, no-shows, and estimated revenue at risk.
- Room operations: room-change rate by hotel and reserved room type; nightly occupancy by assigned room type.
- Drill-through from hotel/segment/month to a booking-level table with source row ID, dates, status, room types, lead time, nights, ADR, and quality flags. No guest PII is present in the source.

## Interpretation notes

- Show `Canceled` and `No-Show` separately. The combined share is useful as a broader booking-failure KPI but should not be labeled cancellation rate.
- Label `ADR × nights` for canceled/no-show bookings as an estimate at risk, not realized lost revenue. Exclude `is_adr_outlier = 1` from ADR and at-risk cards.
- Display ADR and percentages with suitable formatting; do not sum ADR as if it were additive.
