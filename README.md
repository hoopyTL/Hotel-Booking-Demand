# Hotel Booking Demand — End-to-End Business Intelligence & AI System

Dự án xây dựng hệ thống **Business Intelligence (BI) tích hợp Generative AI** trên bộ dữ liệu **Hotel Booking Demand** (119,390 giao dịch đặt phòng của Resort Hotel tại Algarve và City Hotel tại Lisbon, Bồ Đào Nha giai đoạn 2015–2017).

- **Dataset Kaggle:** [Hotel Booking Demand](https://www.kaggle.com/datasets/jessemostipak/hotel-booking-demand)
- **Tài liệu yêu cầu:** [2627.Yêu cầu_unlocked.pdf](file:///Users/hoopy/Developer/Hotel-Booking-Demand/docs/requirements/2627.%20Y%C3%AAu%20c%E1%BA%A7u_unlocked.pdf)
- **Tài liệu Giai đoạn 1 (Phân tích, Profiling & Data Modeling):** [phase1_discovery_and_modeling.md](file:///Users/hoopy/Developer/Hotel-Booking-Demand/docs/phase1_discovery_and_modeling.md)

---

## Kiến trúc Công nghệ

1. **Data Ingestion & ETL:** **SSIS (SQL Server Integration Services)** (thay thế Mage.ai) nạp dữ liệu Full Load / Incremental Load vào vùng Staging, kiểm soát batch & chất lượng dữ liệu qua Metadata.
2. **Data Warehouse (DDS):** **SQL Server** thiết kế theo mô hình **Star Schema** (`dw.Fact_Hotel_Booking` và 9 bảng `dw.Dim_*`).
3. **Data Transformation (Hỗ trợ kết hợp):** SQL Stored Procedures / SSIS Data Flow (hoặc **dbt** trong thư mục `dbt/`).
4. **Business Intelligence:** **Power BI** (Semantic Model, DAX Measures, Overview & Diagnostic Dashboards).
5. **Generative AI:** Ứng dụng Python + LLM tự động tóm tắt KPI và giải thích biến động dựa trên dữ liệu đã kiểm chứng từ DW.

---

## Cấu trúc Thư mục Dự án

```text
Hotel-Booking-Demand/
├── README.md
├── requirements.txt
├── .gitignore
├── data/
│   ├── raw/                  # Đặt file hotel_bookings.csv tải từ Kaggle vào đây
│   ├── batches/              # Các file CSV tách theo năm/tháng để test Incremental Load
│   └── quarantine/           # Xuất các bản ghi lỗi cần kiểm tra
├── docs/
│   ├── requirements/         # Đề bài gốc (2627.Yêu cầu_unlocked.pdf)
│   ├── phase1_discovery_and_modeling.md  # Báo cáo Giai đoạn 1: Profiling & Data Modeling
│   └── reports/              # Báo cáo PDF cuối kỳ & tài liệu thiết kế
├── sql/
│   ├── ddl/
│   │   ├── 01_init_databases_and_schemas.sql  # Tạo DB HotelBooking_DW & schemas (meta, stg, dw)
│   │   ├── 02_ddl_metadata.sql                # Bảng meta.etl_batch_log, watermark, data_quality_log
│   │   ├── 03_ddl_staging.sql                 # Bảng stg.hotel_bookings_raw, clean, error
│   │   └── 04_ddl_dds_dw.sql                  # Bảng Fact_Hotel_Booking & 9 bảng Dim_*
│   └── procedures/
│       └── 05_sp_etl_helpers.sql              # Stored Procedures sinh Dim_Date & ghi log SSIS
├── ssis/
│   └── README.md             # Hướng dẫn thiết kế các SSIS Package (.dtsx)
├── dbt/                      # Thư mục dự phòng/mở rộng cho dbt models & tests
├── scripts/
│   ├── data_profiling.py              # Script thống kê chi tiết lỗi dữ liệu trên CSV
│   └── split_incremental_batches.py   # Tách CSV thành batch Full (2015-2016) & Incremental (2017)
├── bi/
│   ├── dax_measures.md       # Toàn bộ công thức DAX cho Power BI Semantic Model
│   └── dashboards/           # Chứa file Power BI (.pbix)
└── ai/
    └── README.md             # Module Generative AI tóm tắt và giải thích KPI
```

---

## Hướng dẫn Khởi chạy Nhanh

### Bước 1: Chuẩn bị dữ liệu & chạy Data Profiling
1. Tải `hotel_bookings.csv` từ Kaggle và đặt vào `data/raw/hotel_bookings.csv`.
2. Cài đặt thư viện Python và chạy profiling + tách batch:
   ```bash
   pip install -r requirements.txt
   python scripts/data_profiling.py
   python scripts/split_incremental_batches.py
   ```

### Bước 2: Khởi tạo SQL Server (Staging, Metadata & DDS)
Chạy lần lượt các script trong `sql/ddl/` và `sql/procedures/` trên SQL Server Management Studio (SSMS):
1. `sql/ddl/01_init_databases_and_schemas.sql`
2. `sql/ddl/02_ddl_metadata.sql`
3. `sql/ddl/03_ddl_staging.sql`
4. `sql/ddl/04_ddl_dds_dw.sql`
5. `sql/procedures/05_sp_etl_helpers.sql` (sau đó chạy `EXEC [dw].[sp_populate_dim_date];`)
