# Generative AI – AI-Assisted Analytics (`ai/`)

Thư mục này chứa thành phần tích hợp **Generative AI** (theo mục 3.5 của yêu cầu đồ án):
- Kết nối trực tiếp vào **SQL Server Data Warehouse (`HotelBooking_DW`)** để truy xuất các chỉ số KPI đã tính toán chuẩn xác.
- Tự động tạo bản tóm tắt điều hành (**Executive AI Summary**) và giải thích nguyên nhân biến động (tỷ lệ hủy, doanh thu theo mùa, kênh OTA vs Direct) dựa trên số liệu định lượng, chống suy diễn (hallucination).
- Hỗ trợ giao diện hỏi đáp ngôn ngữ tự nhiên (NL2SQL / KPI Q&A) qua Streamlit hoặc script tích hợp Power BI.
