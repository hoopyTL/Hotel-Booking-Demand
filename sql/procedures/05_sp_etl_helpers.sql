-- ============================================================================
-- 05_sp_etl_helpers.sql
-- Các Stored Procedures hỗ trợ SSIS: Khởi tạo Dim_Date, Logging Batch, Clean Staging
-- ============================================================================

USE [HotelBooking_DW];
GO

-- 1. Stored Procedure sinh dữ liệu cho Dim_Date (2013 - 2018)
CREATE OR ALTER PROCEDURE [dw].[sp_populate_dim_date]
    @StartDate DATE = '2013-01-01',
    @EndDate   DATE = '2018-12-31'
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH DateSequence AS (
        SELECT @StartDate AS Dt
        UNION ALL
        SELECT DATEADD(DAY, 1, Dt)
        FROM DateSequence
        WHERE Dt < @EndDate
    )
    INSERT INTO [dw].[Dim_Date] (
        [date_key], [full_date], [day_of_month], [day_of_week], [day_name],
        [is_weekend], [week_of_year], [month_number], [month_name], [quarter], [year], [season]
    )
    SELECT
        CONVERT(INT, FORMAT(Dt, 'yyyyMMdd')) AS [date_key],
        Dt AS [full_date],
        DAY(Dt) AS [day_of_month],
        DATEPART(WEEKDAY, Dt) AS [day_of_week],
        DATENAME(WEEKDAY, Dt) AS [day_name],
        CASE WHEN DATENAME(WEEKDAY, Dt) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END AS [is_weekend],
        DATEPART(ISO_WEEK, Dt) AS [week_of_year],
        MONTH(Dt) AS [month_number],
        DATENAME(MONTH, Dt) AS [month_name],
        DATEPART(QUARTER, Dt) AS [quarter],
        YEAR(Dt) AS [year],
        CASE
            WHEN MONTH(Dt) IN (12, 1, 2) THEN 'Winter'
            WHEN MONTH(Dt) IN (3, 4, 5)  THEN 'Spring'
            WHEN MONTH(Dt) IN (6, 7, 8)  THEN 'Summer'
            ELSE 'Autumn'
        END AS [season]
    FROM DateSequence d
    WHERE NOT EXISTS (
        SELECT 1 FROM [dw].[Dim_Date] existing
        WHERE existing.[date_key] = CONVERT(INT, FORMAT(d.Dt, 'yyyyMMdd'))
    )
    OPTION (MAXRECURSION 0);
END
GO

-- 2. Stored Procedure mở Batch Log mới trong SSIS (Execute SQL Task ở đầu Package)
CREATE OR ALTER PROCEDURE [meta].[sp_start_batch]
    @PackageName NVARCHAR(150),
    @LoadType    VARCHAR(20),
    @SourceFile  NVARCHAR(255) = NULL,
    @BatchId     INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [meta].[etl_batch_log] ([package_name], [load_type], [source_file], [status])
    VALUES (@PackageName, @LoadType, @SourceFile, 'RUNNING');

    SET @BatchId = SCOPE_IDENTITY();
END
GO

-- 3. Stored Procedure đóng Batch Log khi thành công hoặc lỗi
CREATE OR ALTER PROCEDURE [meta].[sp_end_batch]
    @BatchId       INT,
    @Status        VARCHAR(20),
    @RowsExtracted INT = 0,
    @RowsInserted  INT = 0,
    @RowsUpdated   INT = 0,
    @RowsRejected  INT = 0,
    @ErrorMessage  NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [meta].[etl_batch_log]
    SET [end_time]       = SYSDATETIME(),
        [status]         = @Status,
        [rows_extracted] = @RowsExtracted,
        [rows_inserted]  = @RowsInserted,
        [rows_updated]   = @RowsUpdated,
        [rows_rejected]  = @RowsRejected,
        [error_message]  = @ErrorMessage
    WHERE [batch_id] = @BatchId;
END
GO

-- 4. Stored Procedure làm sạch từ stg.hotel_bookings_raw -> stg.hotel_bookings_clean & error
CREATE OR ALTER PROCEDURE [stg].[sp_clean_and_validate_staging]
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 4.1. Đẩy các bản ghi lỗi nghiêm trọng (ADR < 0 hoặc không ép kiểu được ngày/số) sang bảng Quarantine
    INSERT INTO [stg].[hotel_bookings_error] (
        [staging_row_id], [batch_id], [error_code], [error_reason],
        [hotel], [arrival_year], [arrival_month], [arrival_day], [adr], [adults], [children], [babies]
    )
    SELECT
        r.[staging_row_id],
        @BatchId,
        'ERR_NEGATIVE_ADR',
        N'Giá phòng bình quân (ADR) âm: ' + ISNULL(r.[adr], 'NULL'),
        r.[hotel], r.[arrival_date_year], r.[arrival_date_month], r.[arrival_date_day_of_month],
        r.[adr], r.[adults], r.[children], r.[babies]
    FROM [stg].[hotel_bookings_raw] r
    WHERE r.[batch_id] = @BatchId
      AND TRY_CAST(r.[adr] AS DECIMAL(12,2)) < 0;

    -- 4.2. Làm sạch, chuẩn hóa và nạp vào stg.hotel_bookings_clean
    ;WITH ParsedRaw AS (
        SELECT
            r.[staging_row_id],
            r.[batch_id],
            HASHBYTES('SHA2_256', CONCAT_WS('|',
                r.[hotel], r.[is_canceled], r.[lead_time], r.[arrival_date_year],
                r.[arrival_date_month], r.[arrival_date_week_number], r.[arrival_date_day_of_month],
                r.[stays_in_weekend_nights], r.[stays_in_week_nights], r.[adults], r.[children],
                r.[babies], r.[meal], r.[country], r.[market_segment], r.[distribution_channel],
                r.[is_repeated_guest], r.[previous_cancellations], r.[previous_bookings_not_canceled],
                r.[reserved_room_type], r.[assigned_room_type], r.[booking_changes], r.[deposit_type],
                r.[agent], r.[company], r.[days_in_waiting_list], r.[customer_type], r.[adr],
                r.[required_car_parking_spaces], r.[total_of_special_requests],
                r.[reservation_status], r.[reservation_status_date]
            )) AS [row_hash],
            LTRIM(RTRIM(r.[hotel])) AS [hotel],
            CAST(TRY_CAST(r.[is_canceled] AS INT) AS BIT) AS [is_canceled],
            ISNULL(TRY_CAST(r.[lead_time] AS INT), 0) AS [lead_time],
            TRY_CAST(CONCAT(r.[arrival_date_year], '-', r.[arrival_date_month], '-', r.[arrival_date_day_of_month]) AS DATE) AS [arrival_date],
            TRY_CAST(r.[reservation_status_date] AS DATE) AS [reservation_status_date],
            ISNULL(TRY_CAST(r.[stays_in_weekend_nights] AS INT), 0) AS [stays_in_weekend_nights],
            ISNULL(TRY_CAST(r.[stays_in_week_nights] AS INT), 0) AS [stays_in_week_nights],
            ISNULL(TRY_CAST(r.[adults] AS INT), 0) AS [adults],
            CASE WHEN r.[children] IN ('NA', 'NULL', '') OR r.[children] IS NULL THEN 0
                 ELSE ISNULL(TRY_CAST(TRY_CAST(r.[children] AS FLOAT) AS INT), 0)
            END AS [children],
            ISNULL(TRY_CAST(r.[babies] AS INT), 0) AS [babies],
            CASE WHEN r.[meal] IN ('Undefined', 'NA', 'NULL', '') OR r.[meal] IS NULL THEN 'SC'
                 ELSE LTRIM(RTRIM(r.[meal]))
            END AS [meal],
            CASE WHEN r.[country] IN ('NA', 'NULL', '') OR r.[country] IS NULL THEN 'UNK'
                 ELSE LTRIM(RTRIM(r.[country]))
            END AS [country],
            CASE WHEN r.[market_segment] IN ('Undefined', 'NA', 'NULL', '') OR r.[market_segment] IS NULL THEN 'Unknown'
                 ELSE LTRIM(RTRIM(r.[market_segment]))
            END AS [market_segment],
            CASE WHEN r.[distribution_channel] IN ('Undefined', 'NA', 'NULL', '') OR r.[distribution_channel] IS NULL THEN 'Unknown'
                 ELSE LTRIM(RTRIM(r.[distribution_channel]))
            END AS [distribution_channel],
            CAST(ISNULL(TRY_CAST(r.[is_repeated_guest] AS INT), 0) AS BIT) AS [is_repeated_guest],
            ISNULL(TRY_CAST(r.[previous_cancellations] AS INT), 0) AS [previous_cancellations],
            ISNULL(TRY_CAST(r.[previous_bookings_not_canceled] AS INT), 0) AS [previous_bookings_not_canceled],
            LTRIM(RTRIM(r.[reserved_room_type])) AS [reserved_room_type],
            LTRIM(RTRIM(r.[assigned_room_type])) AS [assigned_room_type],
            ISNULL(TRY_CAST(r.[booking_changes] AS INT), 0) AS [booking_changes],
            LTRIM(RTRIM(r.[deposit_type])) AS [deposit_type],
            CASE WHEN r.[agent] IN ('NA', 'NULL', '') OR r.[agent] IS NULL THEN '0'
                 ELSE LTRIM(RTRIM(r.[agent]))
            END AS [agent_id],
            CASE WHEN r.[company] IN ('NA', 'NULL', '') OR r.[company] IS NULL THEN '0'
                 ELSE LTRIM(RTRIM(r.[company]))
            END AS [company_id],
            ISNULL(TRY_CAST(r.[days_in_waiting_list] AS INT), 0) AS [days_in_waiting_list],
            LTRIM(RTRIM(r.[customer_type])) AS [customer_type],
            ISNULL(TRY_CAST(r.[adr] AS DECIMAL(12,2)), 0) AS [adr],
            ISNULL(TRY_CAST(r.[required_car_parking_spaces] AS INT), 0) AS [required_car_parking_spaces],
            ISNULL(TRY_CAST(r.[total_of_special_requests] AS INT), 0) AS [total_of_special_requests],
            LTRIM(RTRIM(r.[reservation_status])) AS [reservation_status]
        FROM [stg].[hotel_bookings_raw] r
        WHERE r.[batch_id] = @BatchId
          AND ISNULL(TRY_CAST(r.[adr] AS DECIMAL(12,2)), 0) >= 0
    ),
    DedupTagged AS (
        SELECT
            p.*,
            ROW_NUMBER() OVER (PARTITION BY p.[row_hash] ORDER BY p.[staging_row_id]) AS [rn]
        FROM ParsedRaw p
    )
    INSERT INTO [stg].[hotel_bookings_clean] (
        [staging_row_id], [batch_id], [row_hash], [hotel], [is_canceled], [lead_time],
        [arrival_date], [booking_date], [reservation_status_date],
        [stays_in_weekend_nights], [stays_in_week_nights], [total_nights],
        [adults], [children], [babies], [total_guests],
        [meal], [country], [market_segment], [distribution_channel],
        [is_repeated_guest], [previous_cancellations], [previous_bookings_not_canceled],
        [reserved_room_type], [assigned_room_type], [booking_changes], [deposit_type],
        [agent_id], [company_id], [days_in_waiting_list], [customer_type],
        [adr], [estimated_revenue], [actual_revenue], [lost_revenue],
        [required_car_parking_spaces], [total_of_special_requests], [reservation_status],
        [is_room_changed], [is_adr_outlier], [is_zero_guest], [is_exact_duplicate]
    )
    SELECT
        d.[staging_row_id],
        d.[batch_id],
        d.[row_hash],
        d.[hotel],
        d.[is_canceled],
        d.[lead_time],
        d.[arrival_date],
        DATEADD(DAY, -d.[lead_time], d.[arrival_date]) AS [booking_date],
        d.[reservation_status_date],
        d.[stays_in_weekend_nights],
        d.[stays_in_week_nights],
        (d.[stays_in_weekend_nights] + d.[stays_in_week_nights]) AS [total_nights],
        d.[adults],
        d.[children],
        d.[babies],
        (d.[adults] + d.[children] + d.[babies]) AS [total_guests],
        d.[meal],
        d.[country],
        d.[market_segment],
        d.[distribution_channel],
        d.[is_repeated_guest],
        d.[previous_cancellations],
        d.[previous_bookings_not_canceled],
        d.[reserved_room_type],
        d.[assigned_room_type],
        d.[booking_changes],
        d.[deposit_type],
        d.[agent_id],
        d.[company_id],
        d.[days_in_waiting_list],
        d.[customer_type],
        d.[adr],
        d.[adr] * (d.[stays_in_weekend_nights] + d.[stays_in_week_nights]) AS [estimated_revenue],
        CASE WHEN d.[is_canceled] = 0 THEN d.[adr] * (d.[stays_in_weekend_nights] + d.[stays_in_week_nights]) ELSE 0 END AS [actual_revenue],
        CASE WHEN d.[is_canceled] = 1 THEN d.[adr] * (d.[stays_in_weekend_nights] + d.[stays_in_week_nights]) ELSE 0 END AS [lost_revenue],
        d.[required_car_parking_spaces],
        d.[total_of_special_requests],
        d.[reservation_status],
        CASE WHEN d.[reserved_room_type] <> d.[assigned_room_type] THEN 1 ELSE 0 END AS [is_room_changed],
        CASE WHEN d.[adr] > 1000 THEN 1 ELSE 0 END AS [is_adr_outlier],
        CASE WHEN (d.[adults] + d.[children] + d.[babies]) = 0 THEN 1 ELSE 0 END AS [is_zero_guest],
        CASE WHEN d.[rn] > 1 THEN 1 ELSE 0 END AS [is_exact_duplicate]
    FROM DedupTagged d
    WHERE NOT EXISTS (
        SELECT 1 FROM [stg].[hotel_bookings_clean] existing
        WHERE existing.[staging_row_id] = d.[staging_row_id]
    );

    -- 4.3. Ghi nhận Data Quality Log
    INSERT INTO [meta].[data_quality_log] ([batch_id], [rule_name], [severity], [affected_rows], [rule_description])
    SELECT @BatchId, 'ERR_NEGATIVE_ADR', 'ERROR', COUNT(*), N'Bản ghi có ADR < 0 bị chuyển sang Quarantine'
    FROM [stg].[hotel_bookings_error] WHERE [batch_id] = @BatchId AND [error_code] = 'ERR_NEGATIVE_ADR'
    UNION ALL
    SELECT @BatchId, 'WARN_ADR_OUTLIER', 'WARNING', COUNT(*), N'Bản ghi có ADR > 1000 được gắn cờ is_adr_outlier'
    FROM [stg].[hotel_bookings_clean] WHERE [batch_id] = @BatchId AND [is_adr_outlier] = 1
    UNION ALL
    SELECT @BatchId, 'WARN_ZERO_GUESTS', 'WARNING', COUNT(*), N'Bản ghi có tổng khách = 0 được gắn cờ is_zero_guest'
    FROM [stg].[hotel_bookings_clean] WHERE [batch_id] = @BatchId AND [is_zero_guest] = 1
    UNION ALL
    SELECT @BatchId, 'INFO_EXACT_DUPLICATE', 'WARNING', COUNT(*), N'Bản ghi trùng lặp hoàn toàn trên 32 cột được gắn cờ is_exact_duplicate'
    FROM [stg].[hotel_bookings_clean] WHERE [batch_id] = @BatchId AND [is_exact_duplicate] = 1;
END
GO

-- 5. Stored Procedure nạp dữ liệu từ stg.hotel_bookings_clean sang các bảng Dim_* và Fact_Hotel_Booking
CREATE OR ALTER PROCEDURE [dw].[sp_load_dds_from_staging]
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 5.1. Upsert Dim_Hotel
    INSERT INTO [dw].[Dim_Hotel] ([hotel_code], [hotel_name], [city], [country])
    SELECT DISTINCT
        CASE WHEN c.[hotel] = 'Resort Hotel' THEN 'H1' ELSE 'H2' END,
        c.[hotel],
        CASE WHEN c.[hotel] = 'Resort Hotel' THEN 'Algarve' ELSE 'Lisbon' END,
        'Portugal'
    FROM [stg].[hotel_bookings_clean] c
    WHERE c.[batch_id] = @BatchId
      AND NOT EXISTS (SELECT 1 FROM [dw].[Dim_Hotel] d WHERE d.[hotel_name] = c.[hotel]);

    -- 5.2. Upsert Dim_Country
    INSERT INTO [dw].[Dim_Country] ([country_iso3], [country_name], [region])
    SELECT DISTINCT
        c.[country],
        CASE WHEN c.[country] = 'UNK' THEN N'Unknown' ELSE c.[country] END,
        N'Unclassified'
    FROM [stg].[hotel_bookings_clean] c
    WHERE c.[batch_id] = @BatchId
      AND NOT EXISTS (SELECT 1 FROM [dw].[Dim_Country] d WHERE d.[country_iso3] = c.[country]);

    -- 5.3. Upsert Dim_Market_Segment
    INSERT INTO [dw].[Dim_Market_Segment] ([market_segment_name], [segment_group])
    SELECT DISTINCT
        c.[market_segment],
        CASE
            WHEN c.[market_segment] IN ('Online TA', 'Offline TA/TO') THEN 'Travel Agency / Operator'
            WHEN c.[market_segment] = 'Direct' THEN 'Direct'
            WHEN c.[market_segment] IN ('Corporate', 'Aviation') THEN 'B2B / Corporate'
            WHEN c.[market_segment] = 'Groups' THEN 'Groups'
            ELSE 'Other / Complementary'
        END
    FROM [stg].[hotel_bookings_clean] c
    WHERE c.[batch_id] = @BatchId
      AND NOT EXISTS (SELECT 1 FROM [dw].[Dim_Market_Segment] d WHERE d.[market_segment_name] = c.[market_segment]);

    -- 5.4. Upsert Dim_Distribution_Channel
    INSERT INTO [dw].[Dim_Distribution_Channel] ([distribution_channel_name])
    SELECT DISTINCT c.[distribution_channel]
    FROM [stg].[hotel_bookings_clean] c
    WHERE c.[batch_id] = @BatchId
      AND NOT EXISTS (SELECT 1 FROM [dw].[Dim_Distribution_Channel] d WHERE d.[distribution_channel_name] = c.[distribution_channel]);

    -- 5.5. Upsert Dim_Room_Type (từ cả reserved và assigned)
    INSERT INTO [dw].[Dim_Room_Type] ([room_type_code])
    SELECT DISTINCT RoomCode
    FROM (
        SELECT [reserved_room_type] AS RoomCode FROM [stg].[hotel_bookings_clean] WHERE [batch_id] = @BatchId
        UNION
        SELECT [assigned_room_type] AS RoomCode FROM [stg].[hotel_bookings_clean] WHERE [batch_id] = @BatchId
    ) r
    WHERE NOT EXISTS (SELECT 1 FROM [dw].[Dim_Room_Type] d WHERE d.[room_type_code] = r.RoomCode);

    -- 5.6. Upsert Dim_Booking_Profile
    INSERT INTO [dw].[Dim_Booking_Profile] (
        [customer_type], [deposit_type], [meal_code], [meal_description], [is_repeated_guest]
    )
    SELECT DISTINCT
        c.[customer_type],
        c.[deposit_type],
        c.[meal],
        CASE c.[meal]
            WHEN 'BB' THEN 'Bed & Breakfast'
            WHEN 'HB' THEN 'Half Board (Breakfast + 1 Meal)'
            WHEN 'FB' THEN 'Full Board (Breakfast, Lunch, Dinner)'
            ELSE 'Self Catering / No Meal Package'
        END,
        c.[is_repeated_guest]
    FROM [stg].[hotel_bookings_clean] c
    WHERE c.[batch_id] = @BatchId
      AND NOT EXISTS (
          SELECT 1 FROM [dw].[Dim_Booking_Profile] d
          WHERE d.[customer_type]     = c.[customer_type]
            AND d.[deposit_type]      = c.[deposit_type]
            AND d.[meal_code]         = c.[meal]
            AND d.[is_repeated_guest] = c.[is_repeated_guest]
      );

    -- 5.7. Upsert Dim_Reservation_Status
    INSERT INTO [dw].[Dim_Reservation_Status] ([reservation_status], [is_canceled])
    SELECT DISTINCT c.[reservation_status], c.[is_canceled]
    FROM [stg].[hotel_bookings_clean] c
    WHERE c.[batch_id] = @BatchId
      AND NOT EXISTS (SELECT 1 FROM [dw].[Dim_Reservation_Status] d WHERE d.[reservation_status] = c.[reservation_status]);

    -- 5.8. Upsert Dim_Agent_Company
    INSERT INTO [dw].[Dim_Agent_Company] ([agent_id], [company_id], [has_agent_flag], [has_company_flag])
    SELECT DISTINCT
        c.[agent_id],
        c.[company_id],
        CASE WHEN c.[agent_id] <> '0' THEN 1 ELSE 0 END,
        CASE WHEN c.[company_id] <> '0' THEN 1 ELSE 0 END
    FROM [stg].[hotel_bookings_clean] c
    WHERE c.[batch_id] = @BatchId
      AND NOT EXISTS (
          SELECT 1 FROM [dw].[Dim_Agent_Company] d
          WHERE d.[agent_id]   = c.[agent_id]
            AND d.[company_id] = c.[company_id]
      );

    -- 5.9. Insert Fact_Hotel_Booking
    INSERT INTO [dw].[Fact_Hotel_Booking] (
        [booking_source_id], [batch_id],
        [arrival_date_key], [booking_date_key], [status_date_key],
        [hotel_key], [country_key], [market_segment_key], [distribution_channel_key],
        [reserved_room_type_key], [assigned_room_type_key],
        [booking_profile_key], [reservation_status_key], [agent_company_key],
        [lead_time], [stays_in_weekend_nights], [stays_in_week_nights], [total_nights],
        [adults], [children], [babies], [total_guests],
        [adr], [estimated_revenue], [actual_revenue], [lost_revenue],
        [booking_changes], [days_in_waiting_list],
        [required_car_parking_spaces], [total_of_special_requests],
        [previous_cancellations], [previous_bookings_not_canceled],
        [is_room_changed], [is_adr_outlier], [is_zero_guest], [is_exact_duplicate]
    )
    SELECT
        c.[staging_row_id] AS [booking_source_id],
        c.[batch_id],
        CONVERT(INT, FORMAT(c.[arrival_date], 'yyyyMMdd')) AS [arrival_date_key],
        CONVERT(INT, FORMAT(c.[booking_date], 'yyyyMMdd')) AS [booking_date_key],
        CONVERT(INT, FORMAT(c.[reservation_status_date], 'yyyyMMdd')) AS [status_date_key],
        dh.[hotel_key],
        dc.[country_key],
        dms.[market_segment_key],
        ddc.[distribution_channel_key],
        dr_res.[room_type_key] AS [reserved_room_type_key],
        dr_ass.[room_type_key] AS [assigned_room_type_key],
        dbp.[booking_profile_key],
        drs.[reservation_status_key],
        dac.[agent_company_key],
        c.[lead_time], c.[stays_in_weekend_nights], c.[stays_in_week_nights], c.[total_nights],
        c.[adults], c.[children], c.[babies], c.[total_guests],
        c.[adr], c.[estimated_revenue], c.[actual_revenue], c.[lost_revenue],
        c.[booking_changes], c.[days_in_waiting_list],
        c.[required_car_parking_spaces], c.[total_of_special_requests],
        c.[previous_cancellations], c.[previous_bookings_not_canceled],
        c.[is_room_changed], c.[is_adr_outlier], c.[is_zero_guest], c.[is_exact_duplicate]
    FROM [stg].[hotel_bookings_clean] c
    INNER JOIN [dw].[Dim_Hotel] dh ON dh.[hotel_name] = c.[hotel]
    INNER JOIN [dw].[Dim_Country] dc ON dc.[country_iso3] = c.[country]
    INNER JOIN [dw].[Dim_Market_Segment] dms ON dms.[market_segment_name] = c.[market_segment]
    INNER JOIN [dw].[Dim_Distribution_Channel] ddc ON ddc.[distribution_channel_name] = c.[distribution_channel]
    INNER JOIN [dw].[Dim_Room_Type] dr_res ON dr_res.[room_type_code] = c.[reserved_room_type]
    INNER JOIN [dw].[Dim_Room_Type] dr_ass ON dr_ass.[room_type_code] = c.[assigned_room_type]
    INNER JOIN [dw].[Dim_Booking_Profile] dbp
        ON dbp.[customer_type]     = c.[customer_type]
       AND dbp.[deposit_type]      = c.[deposit_type]
       AND dbp.[meal_code]         = c.[meal]
       AND dbp.[is_repeated_guest] = c.[is_repeated_guest]
    INNER JOIN [dw].[Dim_Reservation_Status] drs ON drs.[reservation_status] = c.[reservation_status]
    INNER JOIN [dw].[Dim_Agent_Company] dac
        ON dac.[agent_id]   = c.[agent_id]
       AND dac.[company_id] = c.[company_id]
    WHERE c.[batch_id] = @BatchId
      AND NOT EXISTS (
          SELECT 1 FROM [dw].[Fact_Hotel_Booking] f
          WHERE f.[booking_source_id] = c.[staging_row_id]
      );

    -- 5.9b. Insert Fact_Daily_Stay_Snapshot (Phân rã từng đêm lưu trú cho các booking Check-Out có total_nights > 0)
    ;WITH Numbers AS (
        SELECT 0 AS n
        UNION ALL
        SELECT n + 1 FROM Numbers WHERE n < 100
    )
    INSERT INTO [dw].[Fact_Daily_Stay_Snapshot] (
        [booking_source_id], [batch_id],
        [stay_date_key], [hotel_key], [assigned_room_type_key],
        [market_segment_key], [booking_profile_key],
        [night_index], [night_count], [is_weekend_night], [daily_revenue]
    )
    SELECT
        c.[staging_row_id] AS [booking_source_id],
        c.[batch_id],
        CONVERT(INT, FORMAT(DATEADD(DAY, num.n, c.[arrival_date]), 'yyyyMMdd')) AS [stay_date_key],
        dh.[hotel_key],
        dr_ass.[room_type_key] AS [assigned_room_type_key],
        dms.[market_segment_key],
        dbp.[booking_profile_key],
        num.n + 1 AS [night_index],
        1 AS [night_count],
        CASE WHEN DATENAME(WEEKDAY, DATEADD(DAY, num.n, c.[arrival_date])) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END AS [is_weekend_night],
        c.[adr] AS [daily_revenue]
    FROM [stg].[hotel_bookings_clean] c
    INNER JOIN Numbers num
        ON num.n < c.[total_nights]
    INNER JOIN [dw].[Dim_Hotel] dh ON dh.[hotel_name] = c.[hotel]
    INNER JOIN [dw].[Dim_Room_Type] dr_ass ON dr_ass.[room_type_code] = c.[assigned_room_type]
    INNER JOIN [dw].[Dim_Market_Segment] dms ON dms.[market_segment_name] = c.[market_segment]
    INNER JOIN [dw].[Dim_Booking_Profile] dbp
        ON dbp.[customer_type]     = c.[customer_type]
       AND dbp.[deposit_type]      = c.[deposit_type]
       AND dbp.[meal_code]         = c.[meal]
       AND dbp.[is_repeated_guest] = c.[is_repeated_guest]
    WHERE c.[batch_id] = @BatchId
      AND c.[is_canceled] = 0
      AND c.[total_nights] > 0
      AND NOT EXISTS (
          SELECT 1 FROM [dw].[Fact_Daily_Stay_Snapshot] fd
          WHERE fd.[booking_source_id] = c.[staging_row_id]
      )
    OPTION (MAXRECURSION 0);

    -- 5.10. Cập nhật Watermark
    DECLARE @MaxArrivalDate VARCHAR(20);
    SELECT @MaxArrivalDate = CONVERT(VARCHAR(20), MAX([arrival_date]), 23)
    FROM [stg].[hotel_bookings_clean]
    WHERE [batch_id] = @BatchId;

    IF @MaxArrivalDate IS NOT NULL
    BEGIN
        UPDATE [meta].[etl_watermark]
        SET [last_watermark_value] = @MaxArrivalDate,
            [last_batch_id]        = @BatchId,
            [updated_at]           = SYSDATETIME()
        WHERE [entity_name] = 'hotel_bookings';
    END
END
GO
