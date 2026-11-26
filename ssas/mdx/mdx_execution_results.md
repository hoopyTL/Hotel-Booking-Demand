# Kết quả chạy thực tế Bộ Truy Vấn MDX trên SSAS Multidimensional Cube

- **SSAS Server:** `.\SSAS` (Multidimensional Mode)
- **OLAP Database:** `HotelBooking_OLAP`
- **Cube:** `Hotel Booking Cube`
- **Source MDX:** [01_olap_mdx_queries.mdx](01_olap_mdx_queries.mdx)

## Q1. Super Grand Total từ Cube (Slide 73)

```mdx
SELECT
FROM [Hotel Booking Cube];
```

**Result:** `119,389`

## Q2. Dùng mệnh đề WHERE làm Slicer chọn Measure (Slide 74)

```mdx
SELECT
FROM [Hotel Booking Cube]
WHERE [Measures].[Actual Revenue];
```

**Result:** `€25,996,324.21`

## Q3. Đưa Measure lên trục Columns và Hierarchy Năm lên trục Rows (Slides 75-76)

```mdx
SELECT
    {
        [Measures].[Total Bookings],
        [Measures].[Completed Bookings],
        [Measures].[Canceled Bookings],
        [Measures].[Cancellation Rate],
        [Measures].[Actual Revenue],
        [Measures].[Lost Revenue]
    } ON COLUMNS,
    NON EMPTY [Arrival Date].[Date Hierarchy].[Year].MEMBERS ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Total Bookings | Completed Bookings | Canceled Bookings | Cancellation Rate | Actual Revenue | Lost Revenue |
| --- | --- | --- | --- | --- | --- | --- |
| 2015 | 21,996 | 13,854 | 8,142 | 37.02% | €4,511,559.11 | €2,306,557.45 |
| 2016 | 56,707 | 36,370 | 20,337 | 35.86% | €11,673,501.43 | €7,197,099.77 |
| 2017 | 40,686 | 24,941 | 15,745 | 38.70% | €9,811,263.67 | €7,223,579.90 |

## Q4. Kết hợp tập thành viên với tổng [All] bằng cặp ngoặc nhọn {} + NON EMPTY (Slides 77-80)

```mdx
SELECT
    NON EMPTY {
        [Arrival Date].[Date Hierarchy].[Year].MEMBERS,
        [Arrival Date].[Date Hierarchy].[All]
    } ON COLUMNS,
    NON EMPTY {
        [Dim Hotel].[Hotel Hierarchy].[Hotel Name].MEMBERS,
        [Dim Hotel].[Hotel Hierarchy].[All]
    } ON ROWS
FROM [Hotel Booking Cube]
WHERE [Measures].[Actual Revenue];
```

| Row Dimension | 2015 | 2016 | 2017 | All |
| --- | --- | --- | --- | --- |
| Resort Hotel | €2,617,235.57 | €4,811,373.43 | €4,173,305.03 | €11,601,914.03 |
| City Hotel | €1,894,323.54 | €6,862,128.00 | €5,637,958.64 | €14,394,410.18 |
| All | €4,511,559.11 | €11,673,501.43 | €9,811,263.67 | €25,996,324.21 |

## Q5. Truy vấn phân cấp (Hierarchy) sử dụng .CHILDREN & Drill-Down Quarter -> Month (Slides 82-85)

```mdx
SELECT
    {
        [Measures].[Total Bookings],
        [Measures].[Actual Revenue],
        [Measures].[Cancellation Rate]
    } ON COLUMNS,
    NON EMPTY {
        [Arrival Date].[Date Hierarchy].[Year].&[2016].CHILDREN
    } ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Total Bookings | Actual Revenue | Cancellation Rate |
| --- | --- | --- | --- |
| Q1-2016 | 10,963 | €1,516,029.52 | 30.75% |
| Q2-2016 | 16,198 | €3,114,669.39 | 37.49% |
| Q3-2016 | 15,029 | €4,623,986.49 | 35.57% |
| Q4-2016 | 14,517 | €2,418,816.03 | 38.22% |

## Q6. Sắp xếp kết quả bằng hàm ORDER(..., DESC) (Slides 87-88)

```mdx
SELECT
    {
        [Measures].[Total Bookings],
        [Measures].[Actual Revenue],
        [Measures].[Lost Revenue],
        [Measures].[Cancellation Rate]
    } ON COLUMNS,
    ORDER(
        NONEMPTY([Dim Market Segment].[Market Segment Hierarchy].[Market Segment Name].MEMBERS, [Measures].[Total Bookings]),
        [Measures].[Total Bookings],
        BDESC
    ) ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Total Bookings | Actual Revenue | Lost Revenue | Cancellation Rate |
| --- | --- | --- | --- | --- |
| Online TA | 56,477 | €13,714,401.42 | €10,227,646.11 | 36.72% |
| Offline TA/TO | 24,219 | €5,659,554.58 | €2,492,358.15 | 34.32% |
| Groups | 19,810 | €1,869,156.56 | €2,800,543.98 | 61.07% |
| Direct | 12,606 | €4,099,618.57 | €993,409.82 | 15.34% |
| Corporate | 5,295 | €577,912.19 | €196,383.07 | 18.73% |
| Complementary | 743 | €4,812.53 | €269.99 | 13.06% |
| Aviation | 237 | €70,868.36 | €16,578.00 | 21.94% |
| Unknown | 2 | €0.00 | €48.00 | 100.00% |

## Q7. Lọc dữ liệu bằng hàm FILTER() với điều kiện phức AND (Slides 89-91)

```mdx
SELECT
    {
        [Measures].[Total Bookings],
        [Measures].[Canceled Bookings],
        [Measures].[Cancellation Rate],
        [Measures].[Lost Revenue]
    } ON COLUMNS,
    FILTER(
        [Dim Market Segment].[Market Segment Hierarchy].[Market Segment Name].MEMBERS,
        [Measures].[Total Bookings] > 5000 AND [Measures].[Cancellation Rate] > 0.30
    ) ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Total Bookings | Canceled Bookings | Cancellation Rate | Lost Revenue |
| --- | --- | --- | --- | --- |
| Groups | 19,810 | 12,097 | 61.07% | €2,800,543.98 |
| Offline TA/TO | 24,219 | 8,311 | 34.32% | €2,492,358.15 |
| Online TA | 56,477 | 20,739 | 36.72% | €10,227,646.11 |

## Q8. Lọc dữ liệu bằng mệnh đề HAVING (Slide 90)

```mdx
SELECT
    {
        [Measures].[Total Bookings],
        [Measures].[Actual Revenue],
        [Measures].[Cancellation Rate]
    } ON COLUMNS,
    [Dim Country].[Geography Hierarchy].[Country ISO3].MEMBERS
    HAVING [Measures].[Actual Revenue] > 1000000 ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Total Bookings | Actual Revenue | Cancellation Rate |
| --- | --- | --- | --- |
| DEU | 7,287 | €2,068,219.65 | 16.71% |
| ESP | 8,568 | €2,247,108.09 | 25.41% |
| FRA | 10,415 | €3,098,696.28 | 18.57% |
| GBR | 12,128 | €4,112,359.14 | 20.23% |
| IRL | 3,375 | €1,240,002.35 | 24.65% |
| PRT | 48,590 | €5,543,136.74 | 56.64% |

## Q9. Lấy Top 10 Quốc gia có Doanh thu thực tế cao nhất bằng TOPCOUNT (Slide 92)

```mdx
SELECT
    {
        [Measures].[Total Bookings],
        [Measures].[Actual Revenue],
        [Measures].[Lost Revenue],
        [Measures].[Cancellation Rate]
    } ON COLUMNS,
    TOPCOUNT(
        [Dim Country].[Geography Hierarchy].[Country ISO3].MEMBERS,
        10,
        [Measures].[Actual Revenue]
    ) ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Total Bookings | Actual Revenue | Lost Revenue | Cancellation Rate |
| --- | --- | --- | --- | --- |
| PRT | 48,590 | €5,543,136.74 | €8,586,002.05 | 56.64% |
| GBR | 12,128 | €4,112,359.14 | €1,172,172.19 | 20.23% |
| FRA | 10,415 | €3,098,696.28 | €927,816.76 | 18.57% |
| ESP | 8,568 | €2,247,108.09 | €1,057,328.77 | 25.41% |
| DEU | 7,287 | €2,068,219.65 | €556,243.10 | 16.71% |
| IRL | 3,375 | €1,240,002.35 | €412,097.62 | 24.65% |
| ITA | 3,766 | €866,439.42 | €550,431.90 | 35.40% |
| BEL | 2,342 | €759,145.06 | €220,006.80 | 20.24% |
| NLD | 2,104 | €631,663.15 | €168,373.80 | 18.39% |
| CHE | 1,730 | €548,536.40 | €245,661.13 | 24.74% |

## Q10. CROSSJOIN 2 chiều khác nhau: Hotel x Deposit Type (Slides 95-97)

```mdx
SELECT
    {
        [Measures].[Total Bookings],
        [Measures].[Canceled Bookings],
        [Measures].[Cancellation Rate],
        [Measures].[Lost Revenue]
    } ON COLUMNS,
    NON EMPTY CROSSJOIN(
        [Dim Hotel].[Hotel Name].[Hotel Name].MEMBERS,
        [Dim Booking Profile].[Deposit Type].[Deposit Type].MEMBERS
    ) ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Total Bookings | Canceled Bookings | Cancellation Rate | Lost Revenue |
| --- | --- | --- | --- | --- |
| City Hotel | No Deposit | 66,442 | 20,244 | 30.47% | €7,708,165.82 |
| City Hotel | Non Refund | 12,868 | 12,844 | 99.81% | €3,166,272.84 |
| City Hotel | Refundable | 20 | 14 | 70.00% | €10,621.12 |
| Resort Hotel | No Deposit | 38,198 | 9,450 | 24.74% | €5,394,736.10 |
| Resort Hotel | Non Refund | 1,719 | 1,650 | 95.99% | €438,064.19 |
| Resort Hotel | Refundable | 142 | 22 | 15.49% | €9,377.05 |

## Q11. CROSSJOIN 2 Hierarchy khác nhau trong cùng Dimension Date: Year x Season (Slide 96)

```mdx
SELECT
    {
        [Measures].[Total Bookings],
        [Measures].[Actual Revenue],
        [Measures].[Weighted ADR]
    } ON COLUMNS,
    NON EMPTY CROSSJOIN(
        [Arrival Date].[Date Hierarchy].[Year].MEMBERS,
        [Arrival Date].[Season].[Season].MEMBERS
    ) ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Total Bookings | Actual Revenue | Weighted ADR |
| --- | --- | --- | --- |
| 2015 | Autumn | 12,411 | €2,186,045.04 | €81.08 |
| 2015 | Summer | 6,665 | €1,895,992.50 | €121.29 |
| 2015 | Winter | 2,920 | €429,521.57 | €75.22 |
| 2016 | Autumn | 16,051 | €3,050,588.00 | €93.67 |
| 2016 | Spring | 15,730 | €2,737,206.43 | €84.33 |
| 2016 | Summer | 14,927 | €4,479,144.18 | €124.86 |
| 2016 | Winter | 9,999 | €1,406,562.82 | €74.42 |
| 2017 | Spring | 16,943 | €3,410,027.08 | €98.12 |
| 2017 | Summer | 15,885 | €5,225,710.37 | €143.79 |
| 2017 | Winter | 7,858 | €1,175,526.22 | €74.24 |

## Q12. CROSSJOIN trên cả 2 trục Columns và Rows (Slide 98)

```mdx
SELECT
    NON EMPTY CROSSJOIN(
        [Dim Hotel].[Hotel Name].[Hotel Name].MEMBERS,
        {[Measures].[Actual Revenue], [Measures].[Lost Revenue]}
    ) ON COLUMNS,
    NON EMPTY CROSSJOIN(
        [Arrival Date].[Date Hierarchy].[Year].MEMBERS,
        [Dim Market Segment].[Segment Group].[Segment Group].MEMBERS
    ) ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | City Hotel / Actual Revenue | City Hotel / Lost Revenue | Resort Hotel / Actual Revenue | Resort Hotel / Lost Revenue |
| --- | --- | --- | --- | --- |
| 2015 | B2B / Corporate | €69,253.08 | €20,255.44 | €81,786.13 | €19,660.64 |
| 2015 | Direct | €223,928.48 | €51,430.54 | €584,080.83 | €106,816.02 |
| 2015 | Groups | €368,640.81 | €703,928.90 | €134,822.71 | €123,513.94 |
| 2015 | Other / Complementary | €701.00 | €159.99 | €176.00 | €0.00 |
| 2015 | Travel Agency / Operator | €1,231,800.17 | €621,609.64 | €1,816,369.90 | €659,182.34 |
| 2016 | B2B / Corporate | €255,347.41 | €65,350.98 | €63,465.63 | €11,824.90 |
| 2016 | Direct | €697,229.06 | €228,300.87 | €936,978.63 | €193,160.68 |
| 2016 | Groups | €251,791.50 | €667,475.79 | €437,904.00 | €341,822.03 |
| 2016 | Other / Complementary | €1,894.00 | €4.00 | €748.00 | €75.00 |
| 2016 | Travel Agency / Operator | €5,655,866.03 | €3,966,321.49 | €3,372,277.17 | €1,722,764.03 |
| 2017 | B2B / Corporate | €111,943.27 | €49,364.80 | €66,985.03 | €46,504.31 |
| 2017 | Direct | €736,592.53 | €185,050.03 | €920,809.04 | €228,651.68 |
| 2017 | Groups | €360,356.19 | €769,797.86 | €315,641.35 | €194,005.46 |
| 2017 | Other / Complementary | €148.00 | €79.00 | €1,145.53 | €0.00 |
| 2017 | Travel Agency / Operator | €4,428,918.65 | €3,555,930.45 | €2,868,724.08 | €2,194,196.31 |

## Q13. Calculated Member dùng mệnh đề WITH MEMBER (Slides 93-94, 100)

```mdx
WITH
    MEMBER [Measures].[Realized Revenue Ratio] AS
        IIF([Measures].[Estimated Revenue] = 0, NULL, [Measures].[Actual Revenue] / [Measures].[Estimated Revenue]),
        FORMAT_STRING = "0.00%"
    MEMBER [Measures].[Avg Revenue Per Completed Booking] AS
        IIF([Measures].[Completed Bookings] = 0, NULL, [Measures].[Actual Revenue] / [Measures].[Completed Bookings]),
        FORMAT_STRING = "€#,##0.00"
SELECT
    {
        [Measures].[Total Bookings],
        [Measures].[Completed Bookings],
        [Measures].[Actual Revenue],
        [Measures].[Realized Revenue Ratio],
        [Measures].[Avg Revenue Per Completed Booking]
    } ON COLUMNS,
    NON EMPTY [Dim Hotel].[Hotel Hierarchy].[Hotel Name].MEMBERS ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Total Bookings | Completed Bookings | Actual Revenue | Realized Revenue Ratio | Avg Revenue Per Completed Booking |
| --- | --- | --- | --- | --- | --- |
| Resort Hotel | 40,059 | 28,937 | €11,601,914.03 | 66.51% | €400.94 |
| City Hotel | 79,330 | 46,228 | €14,394,410.18 | 56.94% | €311.38 |

## Q14. Truy vấn Measure Group thứ 2 (Fact Daily Stay Snapshot) theo Role-Playing Dimension [Stay Date]

```mdx
SELECT
    {
        [Measures].[Daily Room Nights Occupied],
        [Measures].[Daily Allocated Revenue]
    } ON COLUMNS,
    NON EMPTY CROSSJOIN(
        [Stay Date].[Date Hierarchy].[Year].MEMBERS,
        [Dim Hotel].[Hotel Name].[Hotel Name].MEMBERS
    ) ON ROWS
FROM [Hotel Booking Cube];
```

| Row Dimension | Daily Room Nights Occupied | Daily Allocated Revenue |
| --- | --- | --- |
| 2015 | City Hotel | 20,937 | €1,869,848.20 |
| 2015 | Resort Hotel | 26,795 | €2,580,032.17 |
| 2016 | City Hotel | 65,780 | €6,856,111.46 |
| 2016 | Resort Hotel | 54,037 | €4,822,927.67 |
| 2017 | City Hotel | 48,436 | €5,668,450.52 |
| 2017 | Resort Hotel | 39,045 | €4,198,954.19 |

