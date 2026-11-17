-- ============================================================================
-- 02_ddl_metadata.sql
-- Thiết kế các bảng Metadata phục vụ điều phối SSIS (Full/Incremental Load & DQ)
-- ============================================================================

USE [HotelBooking_DW];
GO

-- 1. Bảng ghi nhận lịch sử chạy Batch/Package SSIS
IF OBJECT_ID(N'meta.etl_batch_log', N'U') IS NULL
BEGIN
    CREATE TABLE [meta].[etl_batch_log] (
        [batch_id]        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [package_name]    NVARCHAR(150)     NOT NULL,
        [load_type]       VARCHAR(20)       NOT NULL, -- 'FULL' | 'INCREMENTAL'
        [source_file]     NVARCHAR(255)     NULL,
        [start_time]      DATETIME2(3)      NOT NULL DEFAULT SYSDATETIME(),
        [end_time]        DATETIME2(3)      NULL,
        [status]          VARCHAR(20)       NOT NULL DEFAULT 'RUNNING', -- 'RUNNING' | 'SUCCESS' | 'FAILED'
        [rows_extracted]  INT               NOT NULL DEFAULT 0,
        [rows_inserted]   INT               NOT NULL DEFAULT 0,
        [rows_updated]    INT               NOT NULL DEFAULT 0,
        [rows_rejected]   INT               NOT NULL DEFAULT 0,
        [error_message]   NVARCHAR(MAX)     NULL
    );
END
GO

-- 2. Bảng quản lý Watermark cho Incremental Load
IF OBJECT_ID(N'meta.etl_watermark', N'U') IS NULL
BEGIN
    CREATE TABLE [meta].[etl_watermark] (
        [entity_name]          VARCHAR(100)  NOT NULL PRIMARY KEY,
        [watermark_column]     VARCHAR(100)  NOT NULL,
        [last_watermark_value] NVARCHAR(100) NOT NULL,
        [last_batch_id]        INT           NULL,
        [updated_at]           DATETIME2(3)  NOT NULL DEFAULT SYSDATETIME()
    );

    -- Khởi tạo mốc mặc định cho bảng hotel_bookings
    INSERT INTO [meta].[etl_watermark] ([entity_name], [watermark_column], [last_watermark_value])
    VALUES ('hotel_bookings', 'arrival_date', '1900-01-01');
END
GO

-- 3. Bảng ghi nhận kết quả kiểm tra chất lượng dữ liệu (Data Quality Log)
IF OBJECT_ID(N'meta.data_quality_log', N'U') IS NULL
BEGIN
    CREATE TABLE [meta].[data_quality_log] (
        [dq_log_id]       BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [batch_id]        INT                  NOT NULL,
        [rule_name]       VARCHAR(100)         NOT NULL,
        [severity]        VARCHAR(20)          NOT NULL, -- 'WARNING' | 'ERROR'
        [affected_rows]   INT                  NOT NULL DEFAULT 0,
        [rule_description] NVARCHAR(500)       NULL,
        [checked_at]      DATETIME2(3)         NOT NULL DEFAULT SYSDATETIME(),
        CONSTRAINT [FK_dq_log_batch] FOREIGN KEY ([batch_id]) REFERENCES [meta].[etl_batch_log]([batch_id])
    );
END
GO
