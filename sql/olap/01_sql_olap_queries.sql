-- ============================================================================
-- 01_sql_olap_queries.sql
-- Bộ truy vấn SQL Extension for OLAP (ROLAP) trên HotelBooking_DW (Schema [dw])
-- Minh họa đầy đủ: Roll-up, Drill-down, Slice, Dice, Pivot,
-- GROUPING SETS, ROLLUP, CUBE và Window Functions (Slides 38-66)
-- ============================================================================

USE [HotelBooking_DW];
GO

-- 1. ROLL-UP (Slide 38, 62-63): Tổng hợp doanh thu & tỷ lệ hủy theo Year -> Quarter -> Month
SELECT
    CASE WHEN GROUPING(d.[year]) = 1 THEN 'ALL YEARS' ELSE CAST(d.[year] AS VARCHAR(10)) END AS [Year],
    CASE WHEN GROUPING(d.[quarter]) = 1 THEN 'ALL QUARTERS' ELSE 'Q' + CAST(d.[quarter] AS VARCHAR(2)) END AS [Quarter],
    CASE WHEN GROUPING(d.[month_number]) = 1 THEN 'ALL MONTHS' ELSE RIGHT('0' + CAST(d.[month_number] AS VARCHAR(2)), 2) END AS [Month],
    COUNT(*) AS [TotalBookings],
    SUM(CASE WHEN s.[is_canceled] = 1 THEN 1 ELSE 0 END) AS [CanceledBookings],
    CAST(100.0 * SUM(CASE WHEN s.[is_canceled] = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS [CancelRatePct],
    CAST(SUM(f.[actual_revenue]) AS DECIMAL(14,2)) AS [ActualRevenue],
    CAST(SUM(f.[lost_revenue]) AS DECIMAL(14,2)) AS [LostRevenue]
FROM [dw].[Fact_Hotel_Booking] f
JOIN [dw].[Dim_Date] d ON f.[arrival_date_key] = d.[date_key]
JOIN [dw].[Dim_Reservation_Status] s ON f.[reservation_status_key] = s.[reservation_status_key]
GROUP BY ROLLUP(d.[year], d.[quarter], d.[month_number])
ORDER BY GROUPING(d.[year]), d.[year], GROUPING(d.[quarter]), d.[quarter], GROUPING(d.[month_number]), d.[month_number];
GO

-- 2. DRILL-DOWN (Slide 43): Đi sâu từ Hotel -> Segment Group -> Market Segment
SELECT
    h.[hotel_name],
    ms.[segment_group],
    ms.[market_segment_name],
    COUNT(*) AS [TotalBookings],
    CAST(100.0 * SUM(CASE WHEN s.[is_canceled] = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS [CancelRatePct],
    CAST(SUM(f.[actual_revenue]) AS DECIMAL(14,2)) AS [ActualRevenue],
    CAST(SUM(f.[lost_revenue]) AS DECIMAL(14,2)) AS [LostRevenue],
    CAST(AVG(CAST(f.[lead_time] AS FLOAT)) AS DECIMAL(10,1)) AS [AvgLeadTime]
FROM [dw].[Fact_Hotel_Booking] f
JOIN [dw].[Dim_Hotel] h ON f.[hotel_key] = h.[hotel_key]
JOIN [dw].[Dim_Market_Segment] ms ON f.[market_segment_key] = ms.[market_segment_key]
JOIN [dw].[Dim_Reservation_Status] s ON f.[reservation_status_key] = s.[reservation_status_key]
GROUP BY ROLLUP(h.[hotel_name], ms.[segment_group], ms.[market_segment_name])
ORDER BY GROUPING(h.[hotel_name]), h.[hotel_name], GROUPING(ms.[segment_group]), ms.[segment_group], [TotalBookings] DESC;
GO

-- 3. GROUPING SETS (Slides 57-61): Tổng hợp đồng thời theo (Hotel, Channel), (Hotel), (Channel), và Grand Total ()
SELECT
    COALESCE(h.[hotel_name], 'ALL HOTELS') AS [Hotel],
    COALESCE(dc.[distribution_channel_name], 'ALL CHANNELS') AS [DistributionChannel],
    COUNT(*) AS [TotalBookings],
    CAST(SUM(f.[actual_revenue]) AS DECIMAL(14,2)) AS [ActualRevenue],
    CAST(SUM(f.[lost_revenue]) AS DECIMAL(14,2)) AS [LostRevenue],
    CAST(100.0 * SUM(CASE WHEN s.[is_canceled] = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS [CancelRatePct]
FROM [dw].[Fact_Hotel_Booking] f
JOIN [dw].[Dim_Hotel] h ON f.[hotel_key] = h.[hotel_key]
JOIN [dw].[Dim_Distribution_Channel] dc ON f.[distribution_channel_key] = dc.[distribution_channel_key]
JOIN [dw].[Dim_Reservation_Status] s ON f.[reservation_status_key] = s.[reservation_status_key]
GROUP BY GROUPING SETS (
    (h.[hotel_name], dc.[distribution_channel_name]),
    (h.[hotel_name]),
    (dc.[distribution_channel_name]),
    ()
)
ORDER BY GROUPING(h.[hotel_name]), h.[hotel_name], GROUPING(dc.[distribution_channel_name]), [TotalBookings] DESC;
GO

-- 4. CUBE (Slides 64-65): Tạo toàn bộ 2^3 = 8 tổ hợp tổng hợp giữa (Hotel, Season, DepositType)
SELECT
    COALESCE(h.[hotel_name], 'ALL HOTELS') AS [Hotel],
    COALESCE(d.[season], 'ALL SEASONS') AS [Season],
    COALESCE(bp.[deposit_type], 'ALL DEPOSITS') AS [DepositType],
    COUNT(*) AS [TotalBookings],
    CAST(100.0 * SUM(CASE WHEN s.[is_canceled] = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS [CancelRatePct],
    CAST(SUM(f.[actual_revenue]) AS DECIMAL(14,2)) AS [ActualRevenue]
FROM [dw].[Fact_Hotel_Booking] f
JOIN [dw].[Dim_Hotel] h ON f.[hotel_key] = h.[hotel_key]
JOIN [dw].[Dim_Date] d ON f.[arrival_date_key] = d.[date_key]
JOIN [dw].[Dim_Booking_Profile] bp ON f.[booking_profile_key] = bp.[booking_profile_key]
JOIN [dw].[Dim_Reservation_Status] s ON f.[reservation_status_key] = s.[reservation_status_key]
GROUP BY CUBE(h.[hotel_name], d.[season], bp.[deposit_type])
ORDER BY GROUPING(h.[hotel_name]), GROUPING(d.[season]), GROUPING(bp.[deposit_type]), [TotalBookings] DESC;
GO

-- 5. SLICE (Slide 44, 49): Cắt lát dữ liệu tại Season = 'Summer'
SELECT
    h.[hotel_name],
    ms.[market_segment_name],
    COUNT(*) AS [SummerBookings],
    CAST(SUM(f.[actual_revenue]) AS DECIMAL(14,2)) AS [SummerActualRevenue],
    CAST(100.0 * SUM(CASE WHEN s.[is_canceled] = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS [SummerCancelRatePct]
FROM [dw].[Fact_Hotel_Booking] f
JOIN [dw].[Dim_Date] d ON f.[arrival_date_key] = d.[date_key]
JOIN [dw].[Dim_Hotel] h ON f.[hotel_key] = h.[hotel_key]
JOIN [dw].[Dim_Market_Segment] ms ON f.[market_segment_key] = ms.[market_segment_key]
JOIN [dw].[Dim_Reservation_Status] s ON f.[reservation_status_key] = s.[reservation_status_key]
WHERE d.[season] = 'Summer'
GROUP BY h.[hotel_name], ms.[market_segment_name]
ORDER BY h.[hotel_name], [SummerActualRevenue] DESC;
GO

-- 6. DICE (Slide 45, 51): Trích khối con theo nhiều chiều:
--    Year IN (2016, 2017) AND Hotel = 'City Hotel' AND DepositType IN ('No Deposit', 'Non Refund')
SELECT
    d.[year],
    bp.[deposit_type],
    bp.[customer_type],
    COUNT(*) AS [Bookings],
    CAST(100.0 * SUM(CASE WHEN s.[is_canceled] = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS [CancelRatePct],
    CAST(SUM(f.[lost_revenue]) AS DECIMAL(14,2)) AS [LostRevenue]
FROM [dw].[Fact_Hotel_Booking] f
JOIN [dw].[Dim_Date] d ON f.[arrival_date_key] = d.[date_key]
JOIN [dw].[Dim_Hotel] h ON f.[hotel_key] = h.[hotel_key]
JOIN [dw].[Dim_Booking_Profile] bp ON f.[booking_profile_key] = bp.[booking_profile_key]
JOIN [dw].[Dim_Reservation_Status] s ON f.[reservation_status_key] = s.[reservation_status_key]
WHERE d.[year] IN (2016, 2017)
  AND h.[hotel_name] = 'City Hotel'
  AND bp.[deposit_type] IN ('No Deposit', 'Non Refund')
GROUP BY d.[year], bp.[deposit_type], bp.[customer_type]
ORDER BY d.[year], bp.[deposit_type], [Bookings] DESC;
GO

-- 7. PIVOT (Slide 46, 50): Xoay bảng Doanh thu thực tế theo Hotel (Hàng) x Season (Cột)
SELECT
    [hotel_name],
    CAST(ISNULL([Spring], 0) AS DECIMAL(14,2)) AS [Spring_Rev],
    CAST(ISNULL([Summer], 0) AS DECIMAL(14,2)) AS [Summer_Rev],
    CAST(ISNULL([Autumn], 0) AS DECIMAL(14,2)) AS [Autumn_Rev],
    CAST(ISNULL([Winter], 0) AS DECIMAL(14,2)) AS [Winter_Rev],
    CAST(ISNULL([Spring], 0) + ISNULL([Summer], 0) + ISNULL([Autumn], 0) + ISNULL([Winter], 0) AS DECIMAL(14,2)) AS [Total_Rev]
FROM (
    SELECT h.[hotel_name], d.[season], f.[actual_revenue]
    FROM [dw].[Fact_Hotel_Booking] f
    JOIN [dw].[Dim_Hotel] h ON f.[hotel_key] = h.[hotel_key]
    JOIN [dw].[Dim_Date] d ON f.[arrival_date_key] = d.[date_key]
) src
PIVOT (
    SUM([actual_revenue]) FOR [season] IN ([Spring], [Summer], [Autumn], [Winter])
) pvt
ORDER BY [hotel_name];
GO

-- 8. OLAP ANALYTICAL WINDOW FUNCTIONS: Tăng trưởng doanh thu theo tháng (MoM %) & Lũy kế theo năm (YTD)
WITH MonthlyRev AS (
    SELECT
        d.[year],
        d.[month_number],
        CONVERT(CHAR(7), d.[full_date], 120) AS [YearMonth],
        CAST(SUM(f.[actual_revenue]) AS DECIMAL(14,2)) AS [ActualRevenue],
        COUNT(*) AS [TotalBookings]
    FROM [dw].[Fact_Hotel_Booking] f
    JOIN [dw].[Dim_Date] d ON f.[arrival_date_key] = d.[date_key]
    GROUP BY d.[year], d.[month_number], CONVERT(CHAR(7), d.[full_date], 120)
)
SELECT
    [YearMonth],
    [TotalBookings],
    [ActualRevenue],
    SUM([ActualRevenue]) OVER (PARTITION BY [year] ORDER BY [month_number]) AS [YTD_Revenue],
    LAG([ActualRevenue]) OVER (ORDER BY [YearMonth]) AS [PrevMonthRevenue],
    CAST(100.0 * ([ActualRevenue] - LAG([ActualRevenue]) OVER (ORDER BY [YearMonth]))
         / NULLIF(LAG([ActualRevenue]) OVER (ORDER BY [YearMonth]), 0) AS DECIMAL(8,2)) AS [MoM_GrowthPct]
FROM MonthlyRev
ORDER BY [YearMonth];
GO
