-- ============================================================================
-- 03_ddl_staging.sql
-- Thiết kế các bảng Staging (Raw, Clean, Error/Quarantine) cho SSIS
-- ============================================================================

USE [HotelBooking_DW];
GO

-- 1. Bảng Raw: Lưu nguyên trạng dữ liệu đọc từ CSV qua SSIS Flat File Source
IF OBJECT_ID(N'stg.hotel_bookings_raw', N'U') IS NULL
BEGIN
    CREATE TABLE [stg].[hotel_bookings_raw] (
        [staging_row_id]                 BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [batch_id]                       INT                  NOT NULL,
        [source_file_name]               NVARCHAR(255)        NULL,
        [loaded_at]                      DATETIME2(3)         NOT NULL DEFAULT SYSDATETIME(),
        [row_hash]                       VARBINARY(32)        NULL,
        -- 32 cột gốc từ hotel_bookings.csv (dùng VARCHAR/NVARCHAR để không lỗi khi gặp chuỗi 'NA' hoặc 'Undefined')
        [hotel]                          VARCHAR(100)         NULL,
        [is_canceled]                    VARCHAR(50)          NULL,
        [lead_time]                      VARCHAR(50)          NULL,
        [arrival_date_year]              VARCHAR(50)          NULL,
        [arrival_date_month]             VARCHAR(50)          NULL,
        [arrival_date_week_number]       VARCHAR(50)          NULL,
        [arrival_date_day_of_month]      VARCHAR(50)          NULL,
        [stays_in_weekend_nights]        VARCHAR(50)          NULL,
        [stays_in_week_nights]           VARCHAR(50)          NULL,
        [adults]                         VARCHAR(50)          NULL,
        [children]                       VARCHAR(50)          NULL,
        [babies]                         VARCHAR(50)          NULL,
        [meal]                           VARCHAR(50)          NULL,
        [country]                        VARCHAR(50)          NULL,
        [market_segment]                 VARCHAR(100)         NULL,
        [distribution_channel]           VARCHAR(100)         NULL,
        [is_repeated_guest]              VARCHAR(50)          NULL,
        [previous_cancellations]         VARCHAR(50)          NULL,
        [previous_bookings_not_canceled] VARCHAR(50)          NULL,
        [reserved_room_type]             VARCHAR(50)          NULL,
        [assigned_room_type]             VARCHAR(50)          NULL,
        [booking_changes]                VARCHAR(50)          NULL,
        [deposit_type]                   VARCHAR(100)         NULL,
        [agent]                          VARCHAR(50)          NULL,
        [company]                        VARCHAR(50)          NULL,
        [days_in_waiting_list]           VARCHAR(50)          NULL,
        [customer_type]                  VARCHAR(100)         NULL,
        [adr]                            VARCHAR(50)          NULL,
        [required_car_parking_spaces]    VARCHAR(50)          NULL,
        [total_of_special_requests]      VARCHAR(50)          NULL,
        [reservation_status]             VARCHAR(50)          NULL,
        [reservation_status_date]        VARCHAR(50)          NULL
    );
END
GO

-- 2. Bảng Clean: Đã ép kiểu, chuẩn hóa 'NA'/'Undefined', tính cột phái sinh & gắn cờ DQ
IF OBJECT_ID(N'stg.hotel_bookings_clean', N'U') IS NULL
BEGIN
    CREATE TABLE [stg].[hotel_bookings_clean] (
        [staging_row_id]                 BIGINT        NOT NULL PRIMARY KEY,
        [batch_id]                       INT           NOT NULL,
        [row_hash]                       VARBINARY(32) NULL,
        [hotel]                          VARCHAR(100)  NOT NULL,
        [is_canceled]                    BIT           NOT NULL,
        [lead_time]                      INT           NOT NULL,
        [arrival_date]                   DATE          NOT NULL,
        [booking_date]                   DATE          NOT NULL,
        [reservation_status_date]        DATE          NOT NULL,
        [stays_in_weekend_nights]        INT           NOT NULL,
        [stays_in_week_nights]           INT           NOT NULL,
        [total_nights]                   INT           NOT NULL,
        [adults]                         INT           NOT NULL,
        [children]                       INT           NOT NULL,
        [babies]                         INT           NOT NULL,
        [total_guests]                   INT           NOT NULL,
        [meal]                           VARCHAR(50)   NOT NULL,
        [country]                        VARCHAR(10)   NOT NULL,
        [market_segment]                 VARCHAR(100)  NOT NULL,
        [distribution_channel]           VARCHAR(100)  NOT NULL,
        [is_repeated_guest]              BIT           NOT NULL,
        [previous_cancellations]         INT           NOT NULL,
        [previous_bookings_not_canceled] INT           NOT NULL,
        [reserved_room_type]             VARCHAR(10)   NOT NULL,
        [assigned_room_type]             VARCHAR(10)   NOT NULL,
        [booking_changes]                INT           NOT NULL,
        [deposit_type]                   VARCHAR(100)  NOT NULL,
        [agent_id]                       VARCHAR(20)   NOT NULL,
        [company_id]                     VARCHAR(20)   NOT NULL,
        [days_in_waiting_list]           INT           NOT NULL,
        [customer_type]                  VARCHAR(100)  NOT NULL,
        [adr]                            DECIMAL(12,2) NOT NULL,
        [estimated_revenue]              DECIMAL(14,2) NOT NULL,
        [actual_revenue]                 DECIMAL(14,2) NOT NULL,
        [lost_revenue]                   DECIMAL(14,2) NOT NULL,
        [required_car_parking_spaces]    INT           NOT NULL,
        [total_of_special_requests]      INT           NOT NULL,
        [reservation_status]             VARCHAR(50)   NOT NULL,
        -- Data Quality & Operational Flags
        [is_room_changed]                BIT           NOT NULL DEFAULT 0,
        [is_adr_outlier]                 BIT           NOT NULL DEFAULT 0,
        [is_zero_guest]                  BIT           NOT NULL DEFAULT 0,
        [is_exact_duplicate]             BIT           NOT NULL DEFAULT 0
    );
END
GO

-- 3. Bảng Error (Quarantine): Chứa các bản ghi vi phạm lỗi nghiêm trọng (vd: adr < 0, sai định dạng ngày)
IF OBJECT_ID(N'stg.hotel_bookings_error', N'U') IS NULL
BEGIN
    CREATE TABLE [stg].[hotel_bookings_error] (
        [error_row_id]    BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [staging_row_id]  BIGINT               NULL,
        [batch_id]        INT                  NOT NULL,
        [error_code]      VARCHAR(50)          NOT NULL,
        [error_reason]    NVARCHAR(500)        NOT NULL,
        [hotel]           VARCHAR(100)         NULL,
        [arrival_year]    VARCHAR(50)          NULL,
        [arrival_month]   VARCHAR(50)          NULL,
        [arrival_day]     VARCHAR(50)          NULL,
        [adr]             VARCHAR(50)          NULL,
        [adults]          VARCHAR(50)          NULL,
        [children]        VARCHAR(50)          NULL,
        [babies]          VARCHAR(50)          NULL,
        [logged_at]       DATETIME2(3)         NOT NULL DEFAULT SYSDATETIME()
    );
END
GO
