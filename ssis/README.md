# SSIS Solution Guide (`ssis/`)

Thư mục này chứa project **SQL Server Integration Services (SSIS)** (`HotelBooking_ETL`) thực hiện quy trình ETL chuẩn công nghiệp từ file CSV nguồn qua vùng Staging sang Kho dữ liệu đa chiều (DDS) trên SQL Server (`HotelBooking_DW`), kết hợp kiểm soát Metadata, Watermark và Audit chất lượng dữ liệu.

---

## Kiến trúc 5 SSIS Package (Pure SSIS Data Flow)

1. **`00_Master_Orchestrator.dtsx`** — *Điều phối tổng thể (FULL / INCREMENTAL)*
   * **Control Flow:**
     1. `Start Pipeline`: Kiểm tra `LoadType` (`FULL` / `INCREMENTAL`), chống nạp trùng file `INCREMENTAL` sau lần `FULL` gần nhất, khởi tạo `batch_id` trong `meta.etl_batch_log`.
     2. `Prepare Full Load`: Nếu `LoadType = 'FULL'`, xóa sạch các bảng Fact, Staging Clean/Error và reset `meta.etl_watermark` trong cùng Transaction.
     3. Gọi tuần tự 4 package con qua `Execute Package Task` (`UseProjectReference = True`): `01` $\rightarrow$ `02` $\rightarrow$ `03` $\rightarrow$ `04`.
     4. `End Pipeline`: Ghi nhận trạng thái `SUCCESS` và tổng hợp `rows_extracted`, `rows_inserted`, `rows_rejected`.
   * **Event Handler (`OnError`):** Tự động cập nhật `status = 'FAILED'` + `System::ErrorDescription` vào `meta.etl_batch_log`.

2. **`01_Ingest_CSV_To_RawStaging.dtsx`** — *Nạp dữ liệu thô CSV $\rightarrow$ Staging Raw*
   * **Data Flow Task (`Load CSV to Staging`):**
     `Flat File Source (Read CSV — 32 cột VARCHAR)` $\rightarrow$ `Derived Column (Add Batch Info: batch_id, source_file_name)` $\rightarrow$ `Row Count (User::RowsRead)` $\rightarrow$ `OLE DB Destination FastLoad ([stg].[hotel_bookings_raw])`.

3. **`02_Validate_And_Clean_Staging.dtsx`** — *Kiểm định chất lượng & Làm sạch Staging*
   * **Data Flow Task (`DFT - Validate and Clean Staging`):**
     * `OLE DB Source (Read Raw Staging)`: Đọc lô dữ liệu `@BatchId`, xử lý bỏ ký tự `\r`, tính `SHA2_256 row_hash` & gắn cờ `is_exact_duplicate`, kiểm tra lỗi kiểu dữ liệu / ngày tháng / `ADR < 0`.
     * $\rightarrow$ **`Conditional Split (Split Valid vs Error)`** tách thành 2 nhánh rõ ràng:
       * **Nhánh Lỗi (`Error Rows`):** `Derived Column (Add Error Reason)` $\rightarrow$ `Row Count (RowsRejected)` $\rightarrow$ `OLE DB Destination ([stg].[hotel_bookings_error] — Quarantine)`.
       * **Nhánh Hợp lệ (`Valid Rows`):** `Derived Column (Compute Metrics and DQ Flags: total_nights, total_guests, estimated_revenue, actual_revenue, lost_revenue, is_room_changed, is_adr_outlier, is_zero_guest)` $\rightarrow$ `Row Count (RowsClean)` $\rightarrow$ `OLE DB Destination ([stg].[hotel_bookings_clean])`.
   * **Audit & Đối soát:** Ghi chi tiết quy tắc vào `meta.data_quality_log`, chạy `Check Row Counts` khẳng định `Raw = Clean + Rejected` và cập nhật `meta.etl_batch_log`.

4. **`03_Load_DDS_Dimensions.dtsx`** — *Nạp 9 bảng Dimension (Data Flow + Lookup)*
   * `Load Date`: Sinh dãy ngày liên tục vào `dw.Dim_Date`.
   * **8 Data Flow Tasks** (`Dim_Hotel`, `Dim_Country`, `Dim_Market_Segment`, `Dim_Distribution_Channel`, `Dim_Room_Type`, `Dim_Booking_Profile`, `Dim_Reservation_Status`, `Dim_Agent_Company`), mỗi bảng gồm:
     `OLE DB Source (DISTINCT)` $\rightarrow$ **`Lookup Transformation` (`NoMatchBehavior = Redirect rows to no match output`)** $\rightarrow$ `Row Count` $\rightarrow$ `OLE DB Destination (dw.Dim_*)`.
   * `Check Dimension Keys`: Kiểm tra toàn vẹn 100% khóa trước khi sang bước nạp Fact.

5. **`04_Load_DDS_Fact.dtsx`** — *Nạp 2 bảng Fact (Data Flow + chuỗi 9 Lookup)*
   * **Data Flow Task 1 (`DFT - Load Fact_Hotel_Booking`):**
     `OLE DB Source (stg.hotel_bookings_clean)` $\rightarrow$ `Lookup Existing Fact` *(chống trùng `booking_source_id`)* $\rightarrow$ **chuỗi 9 `Lookup Transformation`** tra Surrogate Keys (`Dim_Hotel`, `Dim_Country`, `Dim_Market_Segment`, `Dim_Distribution_Channel`, `Reserved Room`, `Assigned Room`, `Dim_Booking_Profile`, `Dim_Reservation_Status`, `Dim_Agent_Company`) $\rightarrow$ `Row Count` $\rightarrow$ `OLE DB Destination ([dw].[Fact_Hotel_Booking])`.
   * **Data Flow Task 2 (`DFT - Load Fact_Daily_Stay_Snapshot`):**
     `OLE DB Source (Expand Daily Stays)` $\rightarrow$ `Lookup Existing Daily Stay` *(chống trùng)* $\rightarrow$ `Row Count` $\rightarrow$ `OLE DB Destination ([dw].[Fact_Daily_Stay_Snapshot])`.
   * **Đối soát & Watermark:** `Check Fact Totals` đối soát số dòng/đêm/doanh thu giữa Clean Staging và 2 bảng Fact, sau đó cập nhật `meta.etl_watermark` và đóng `meta.etl_batch_log`.

---

## Hướng dẫn chạy & demo kịch bản FULL $\rightarrow$ INCREMENTAL

### Bước 1: Tạo 2 file batch mô phỏng
```powershell
python scripts\split_incremental_batches.py
# Tạo ra data\batches\batch_01_initial_2015_2016.csv (78,703 dòng)
# và     data\batches\batch_02_incremental_2017.csv (40,687 dòng)
```

### Bước 2: Chạy bằng `DTExec.exe` (SQL Server 2022 Integration Services)
```powershell
$dtexec = 'C:\Program Files\Microsoft SQL Server\160\DTS\Binn\DTExec.exe'
$ispac  = 'C:\Users\ADMIN\Desktop\Hotel-Booking-Demand\ssis\HotelBooking_ETL\bin\Development\HotelBooking_ETL.ispac'

# 1. Chạy FULL Load với batch 2015-2016
& $dtexec /Project $ispac /Package '00_Master_Orchestrator.dtsx' `
  /SET '\Package.Variables[$Package::LoadType];FULL' `
  /SET '\Package.Variables[$Package::SourceFile];C:\Users\ADMIN\Desktop\Hotel-Booking-Demand\data\batches\batch_01_initial_2015_2016.csv'

# 2. Chạy INCREMENTAL Load với batch 2017 (nối tiếp vào DW & cập nhật Watermark)
& $dtexec /Project $ispac /Package '00_Master_Orchestrator.dtsx' `
  /SET '\Package.Variables[$Package::LoadType];INCREMENTAL' `
  /SET '\Package.Variables[$Package::SourceFile];C:\Users\ADMIN\Desktop\Hotel-Booking-Demand\data\batches\batch_02_incremental_2017.csv'
```

### Mở trong Visual Studio (chụp sơ đồ báo cáo)
Mở [HotelBooking_ETL.slnx](HotelBooking_ETL/HotelBooking_ETL.slnx) trong Visual Studio $\rightarrow$ mở từng package `.dtsx` $\rightarrow$ chọn menu **Format $\rightarrow$ Auto Layout $\rightarrow$ Diagram** để tự căn chỉnh bố cục các hộp Control Flow và Data Flow gọn đẹp.
