# Danh mục DAX Measures cho Power BI (`bi/dax_measures.md`)

Tạo một bảng trống tên `_Measures` trong Power BI Semantic Model và thêm các công thức DAX dưới đây:

```dax
// =========================================================
// 1. BOOKING VOLUME KPIs
// =========================================================
Total Bookings = COUNTROWS('Fact_Hotel_Booking')

Completed Bookings = 
CALCULATE(
    [Total Bookings],
    'Dim_Reservation_Status'[is_canceled] = FALSE()
)

Canceled Bookings = 
CALCULATE(
    [Total Bookings],
    'Dim_Reservation_Status'[is_canceled] = TRUE()
)

Cancellation Rate (%) = 
DIVIDE([Canceled Bookings], [Total Bookings], 0)

No-Show Bookings = 
CALCULATE(
    [Total Bookings],
    'Dim_Reservation_Status'[reservation_status] = "No-Show"
)

No-Show Rate (%) = 
DIVIDE([No-Show Bookings], [Total Bookings], 0)

// =========================================================
// 2. REVENUE & PRICING KPIs
// =========================================================
Total Estimated Revenue = SUM('Fact_Hotel_Booking'[estimated_revenue])

Total Actual Revenue = SUM('Fact_Hotel_Booking'[actual_revenue])

Total Lost Revenue = SUM('Fact_Hotel_Booking'[lost_revenue])

Revenue Loss Ratio (%) = 
DIVIDE([Total Lost Revenue], [Total Estimated Revenue], 0)

Total Room Nights Sold = 
CALCULATE(
    SUM('Fact_Hotel_Booking'[total_nights]),
    'Dim_Reservation_Status'[is_canceled] = FALSE()
)

Weighted ADR = 
DIVIDE([Total Actual Revenue], [Total Room Nights Sold], 0)

// =========================================================
// 3. OPERATIONAL & GUEST KPIs
// =========================================================
Avg Lead Time (Days) = AVERAGE('Fact_Hotel_Booking'[lead_time])

Avg Length of Stay (ALOS) = 
CALCULATE(
    AVERAGE('Fact_Hotel_Booking'[total_nights]),
    'Dim_Reservation_Status'[is_canceled] = FALSE()
)

Total Guests Checked-In = 
CALCULATE(
    SUM('Fact_Hotel_Booking'[total_guests]),
    'Dim_Reservation_Status'[is_canceled] = FALSE()
)

Room Change Count = 
CALCULATE(
    [Total Bookings],
    'Fact_Hotel_Booking'[is_room_changed] = TRUE()
)

Room Change Rate (%) = 
DIVIDE([Room Change Count], [Total Bookings], 0)

Repeat Guest Bookings = 
CALCULATE(
    [Total Bookings],
    'Dim_Booking_Profile'[is_repeated_guest] = TRUE()
)

Repeat Guest Rate (%) = 
DIVIDE([Repeat Guest Bookings], [Total Bookings], 0)

// =========================================================
// 4. DAILY OCCUPANCY & ALLOCATED REVENUE (Fact_Daily_Stay_Snapshot)
// =========================================================
Daily Room Nights Occupied = SUM('Fact_Daily_Stay_Snapshot'[night_count])

Daily Allocated Revenue = SUM('Fact_Daily_Stay_Snapshot'[daily_revenue])

Weekend Allocated Revenue = 
CALCULATE(
    [Daily Allocated Revenue],
    'Fact_Daily_Stay_Snapshot'[is_weekend_night] = TRUE()
)

Weekday Allocated Revenue = 
CALCULATE(
    [Daily Allocated Revenue],
    'Fact_Daily_Stay_Snapshot'[is_weekend_night] = FALSE()
)
```
