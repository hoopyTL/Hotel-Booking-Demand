# Power BI Reporting & Dashboard (`bi/`)

Thư mục này chứa trọn bộ **Power BI Project (`.pbip`)** kết nối trực tiếp tới Data Warehouse **`HotelBooking_DW`** trên SQL Server (`.\SQLEXPRESS`), cùng danh mục công thức DAX.

## Cấu trúc thư mục

* [bi/dashboards/HotelBooking_BI.pbip](dashboards/HotelBooking_BI.pbip): File dự án Power BI chính — mở trực tiếp bằng **Power BI Desktop**.
* `bi/dashboards/HotelBooking_BI.SemanticModel/`: Mô hình ngữ nghĩa (**TMDL v4.0**) gồm:
  * **Power Query Parameters:** `SqlServerName` (`.\SQLEXPRESS`), `DatabaseName` (`HotelBooking_DW`) — dễ dàng đổi server khi chấm bài trên máy khác.
  * **14 bảng dữ liệu:** 9 bảng `dw.Dim_*`, 2 bảng Fact (`dw.Fact_Hotel_Booking`, `dw.Fact_Daily_Stay_Snapshot`), 2 bảng Audit Metadata (`meta.etl_batch_log`, `meta.data_quality_log`) và bảng measure `_Measures`.
  * **18 Relationships:** Đầy đủ Star / Galaxy Schema (bao gồm Role-playing `Dim_Date` cho Arrival/Booking/Status/Stay Date và `Dim_Room_Type` cho Reserved/Assigned Room Type).
  * **6 Hierarchies:** `Date Hierarchy`, `Season Hierarchy`, `Hotel Hierarchy`, `Geography Hierarchy`, `Market Segment Hierarchy`, `Booking Profile Hierarchy`.
  * **27 DAX Measures:** Chia 5 Display Folders (`01. Booking Volume`, `02. Revenue & Pricing`, `03. Operational & Guest`, `04. Daily Occupancy`, `05. Diagnostic & Role-Playing`).
* `bi/dashboards/HotelBooking_BI.Report/`: Báo cáo (**PBIR v4.0**) gồm **3 trang Dashboard**:
  1. **`1. Overview (Descriptive)`** — KPI tổng quan, xu hướng doanh thu thực tế vs doanh thu mất do hủy & tỷ lệ hủy theo tháng, so sánh Resort vs City Hotel, phân bố theo phân khúc/kênh bán/mùa, 5 bộ lọc đa chiều.
  2. **`2. Detailed (Diagnostic)`** — Phân tích nguyên nhân hủy phòng theo nhóm Lead Time, chính sách đặt cọc (`deposit_type`), loại khách (`customer_type`), tỷ lệ đổi hạng phòng (`is_room_changed`), ma trận định lượng có **Drill-Down** (`Hotel → Segment Group → Market Segment`) và hỗ trợ **Drill-Through** từ trang Overview (chuột phải vào Hotel hoặc Market Segment $\rightarrow$ *Drill through* $\rightarrow$ *2. Detailed (Diagnostic)*).
  3. **`3. Daily Occupancy & ETL Audit`** — Phân tích công suất đêm phòng & doanh thu phân bổ theo từng ngày lịch (`Fact_Daily_Stay_Snapshot`, Weekend vs Weekday) và bảng giám sát lịch sử chạy SSIS + kiểm tra chất lượng dữ liệu (`meta.etl_batch_log`, `meta.data_quality_log`).
* [bi/dax_measures.md](dax_measures.md): Tài liệu công thức DAX tham khảo.

---

## Hướng dẫn mở & xuất file `.pbix` để nộp

1. Đảm bảo SQL Server (`.\SQLEXPRESS`) đang chạy và database `HotelBooking_DW` đã có dữ liệu (SSIS đã chạy xong).
2. Mở file [bi/dashboards/HotelBooking_BI.pbip](dashboards/HotelBooking_BI.pbip) bằng **Power BI Desktop**.
3. Bấm nút **Refresh** trên thanh Home để nạp dữ liệu từ `HotelBooking_DW` vào mô hình.
   * *(Nếu Power BI hỏi quyền kết nối SQL Server, chọn **Windows → Use my current credentials → Connect**, và chấp nhận kết nối không mã hóa nếu dùng `.\SQLEXPRESS` nội bộ.)*
   * *(Nếu máy khác dùng tên SQL Server khác `.\SQLEXPRESS`, vào **Transform data → Edit parameters** để sửa `SqlServerName`.)*
4. Kiểm tra đủ 3 trang Dashboard, thử thao tác lọc (Slicers), Drill-down trên biểu đồ/ma trận và chuột phải **Drill-through** sang trang 2.
5. Vào **File → Save As**, chọn định dạng **Power BI files (`.pbix`)** và lưu thành `bi/dashboards/HotelBooking_BI.pbix` để nộp bài theo yêu cầu đề.
