# SSIS Solution Guide (`ssis/`)

Thư mục này chứa project **SQL Server Integration Services (SSIS)** thay thế cho Mage.ai để thực hiện thu thập, làm sạch và nạp dữ liệu vào SQL Server.

## Cấu trúc các Package khuyến nghị

1. **`00_Master_Orchestrator.dtsx`**
   - Điều phối toàn bộ pipeline theo tham số `@[$Project::LoadType]` (`FULL` hoặc `INCREMENTAL`).
   - Gọi tuần tự các package con thông qua `Execute Package Task`.

2. **`01_Ingest_CSV_To_RawStaging.dtsx`**
   - **Control Flow:**
     1. `Execute SQL Task` — Gọi `EXEC [meta].[sp_start_batch]` lấy `@[User::BatchId]`.
     2. Nếu `LoadType == 'FULL'`, thực hiện `TRUNCATE TABLE [stg].[hotel_bookings_raw]`.
     3. `Data Flow Task` — Đọc từ `Flat File Source` (`hotel_bookings.csv` hoặc các file trong `data/batches/`), qua `Derived Column` thêm `batch_id`, `source_file_name`, `RowCount`, và ghi vào `OLE DB Destination` (`[stg].[hotel_bookings_raw]`).
     4. `Execute SQL Task` — Gọi `EXEC [meta].[sp_end_batch]` cập nhật trạng thái `SUCCESS` và số dòng đã đọc.
   - **Event Handlers (`OnError`):**
     - Gọi `EXEC [meta].[sp_end_batch]` với `@Status = 'FAILED'` và `@[System::ErrorDescription]`.

3. **`02_Validate_And_Clean_Staging.dtsx`**
   - Chuyển dữ liệu từ `[stg].[hotel_bookings_raw]` sang `[stg].[hotel_bookings_clean]`.
   - Tách các dòng lỗi nghiêm trọng (`adr < 0`, lỗi parse ngày) sang `[stg].[hotel_bookings_error]` (qua `Conditional Split` trong SSIS hoặc Stored Procedure) và ghi log vào `[meta].[data_quality_log]`.

4. **`03_Load_DDS_Dimensions.dtsx`**
   - Nạp dữ liệu vào các bảng `dw.Dim_*` (sử dụng `Lookup Transformation` ở chế độ *Redirect rows to no match output* để chỉ insert các giá trị Dimension mới).

5. **`04_Load_DDS_Fact.dtsx`**
   - Thực hiện `Lookup` khóa Surrogate Key từ các bảng `dw.Dim_*` và nạp vào `dw.Fact_Hotel_Booking`, sau đó cập nhật `[meta].[etl_watermark]`.
