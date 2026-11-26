# OLAP — SSAS Multidimensional Cube & MDX (`ssas/`)

Thư mục này chứa giải pháp **OLAP Multidimensional** theo đúng chuẩn **Microsoft BI Suite** và nội dung Chương 5 (*BI Application* — SSAS Multidimensional Cube + MDX):

## Kiến trúc OLAP Cube đã Deploy trên `.\SSAS`

* **SSAS Server:** `.\SSAS` (SQL Server 2022 Developer Edition — **Multidimensional Mode**, MOLAP Storage)
* **OLAP Database:** `HotelBooking_OLAP`
* **Cube:** `Hotel Booking Cube`
* **Data Source:** `.\SQLEXPRESS` $\rightarrow$ `HotelBooking_DW` (`dw.*`)
* **Data Source View:** `HotelBooking_DSV` (11 bảng Star/Galaxy Schema + Named Calculations `FullDateLabel`, `QuarterLabel`, `YearMonth`, `SeasonLabel`, `RoomChangedCount`, `AdrOutlierCount`, `ZeroGuestCount`, `ExactDuplicateCount`).
* **9 Dimensions (13 Role-Playing CubeDimensions):**
  * `Dim Date` (Role-playing: `Arrival Date`, `Booking Date`, `Status Date`, `Stay Date`) — gồm 2 Hierarchies: `Date Hierarchy` (`Year → Quarter Label → Year Month → Date Key`) và `Season Hierarchy` (`Year → Season Label → Date Key`).
  * `Dim Hotel` — Hierarchy `Hotel Hierarchy` (`Country → City → Hotel Name`).
  * `Dim Country` — Hierarchy `Geography Hierarchy` (`Region → Country ISO3`).
  * `Dim Market Segment` — Hierarchy `Market Segment Hierarchy` (`Segment Group → Market Segment Name`).
  * `Dim Distribution Channel`, `Dim Room Type` (Role-playing: `Reserved Room Type`, `Assigned Room Type`), `Dim Booking Profile`, `Dim Reservation Status` (`Status Hierarchy`), `Dim Agent Company`.
* **2 Measure Groups + 8 MDX Calculated Members:**
  * `Fact Hotel Booking`: `Total Bookings`, `Actual Revenue`, `Estimated Revenue`, `Lost Revenue`, `Total Nights`, `Weekend Nights`, `Week Nights`, `Total Guests`, `Lead Time Sum`, `ADR Sum`, `Special Requests`, `Booking Changes`, `Room Changed Count`.
  * `Fact Daily Stay Snapshot`: `Daily Room Nights Occupied`, `Daily Allocated Revenue`.
  * **Built-in Calculated Measures:** `Canceled Bookings`, `Completed Bookings`, `Cancellation Rate`, `Revenue Loss Ratio`, `Avg Lead Time`, `Room Nights Sold`, `Weighted ADR`, `Room Change Rate`.

---

## Cấu trúc thư mục

* [ssas/scripts/deploy_ssas_cube.ps1](scripts/deploy_ssas_cube.ps1): Script tự động dựng, Deploy & Process Full toàn bộ Cube lên `.\SSAS` và xuất XMLA.
* [ssas/HotelBooking_OLAP/HotelBooking_OLAP.xmla](HotelBooking_OLAP/HotelBooking_OLAP.xmla): File XMLA định nghĩa toàn bộ OLAP Database `HotelBooking_OLAP`.
* [ssas/mdx/01_olap_mdx_queries.mdx](mdx/01_olap_mdx_queries.mdx): **14 truy vấn MDX** phủ trọn các kỹ thuật trong bài giảng (`SELECT`, `WHERE` Slicer, `NON EMPTY`, `{}` Sets, `.MEMBERS`, `.CHILDREN`, `ORDER`, `FILTER`, `HAVING`, `TOPCOUNT`, `CROSSJOIN` 1 trục & 2 trục, `WITH MEMBER`, Role-Playing & Measure Group 2).
* [ssas/scripts/run_mdx_queries.ps1](scripts/run_mdx_queries.ps1): Script thực thi tự động toàn bộ 14 truy vấn MDX qua `AdomdClient` và xuất kết quả ra Markdown.
* [ssas/mdx/mdx_execution_results.md](mdx/mdx_execution_results.md): Bảng kết quả chạy thực tế từ Cube `.\SSAS`.
* [sql/olap/01_sql_olap_queries.sql](../sql/olap/01_sql_olap_queries.sql): Bộ **8 truy vấn SQL Extension for OLAP** (`ROLLUP`, `DRILL-DOWN`, `GROUPING SETS`, `CUBE`, `SLICE`, `DICE`, `PIVOT`, Window Functions MoM/YTD).

---

## Cách demo trực tiếp trên SSMS & Excel PivotTable

1. **Chạy MDX trên SSMS (y hệt slide bài giảng):**
   * Mở **SQL Server Management Studio (SSMS)** $\rightarrow$ **Connect** $\rightarrow$ chọn **Server type: `Analysis Services`** $\rightarrow$ **Server name: `.\SSAS`** $\rightarrow$ Connect.
   * Mở `Databases → HotelBooking_OLAP → Cubes → Hotel Booking Cube` (có thể chuột phải chọn **Browse** để kéo thả Cube trực quan).
   * Bấm **New Query (MDX)** $\rightarrow$ mở file [ssas/mdx/01_olap_mdx_queries.mdx](mdx/01_olap_mdx_queries.mdx) và bôi đen chạy từng câu `Q1`–`Q14`.
2. **Kết nối Excel PivotTable vào OLAP Cube:**
   * Mở **Excel** $\rightarrow$ **Data** $\rightarrow$ **Get Data** $\rightarrow$ **From Database** $\rightarrow$ **From Analysis Services** $\rightarrow$ nhập Server name `.\SSAS` $\rightarrow$ chọn `HotelBooking_OLAP` $\rightarrow$ `Hotel Booking Cube` $\rightarrow$ kéo thả Dimensions & Measures trực tiếp như PivotTable OLAP.
3. **Redeploy / Process lại Cube sau khi chạy Incremental Load SSIS:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File ssas\scripts\deploy_ssas_cube.ps1
   powershell -ExecutionPolicy Bypass -File ssas\scripts\run_mdx_queries.ps1
   ```
