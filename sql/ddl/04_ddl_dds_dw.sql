-- ============================================================================
-- 04_ddl_dds_dw.sql
-- Thiết kế Dimensional Data Store (Star Schema) trong schema [dw]
-- ============================================================================

USE [HotelBooking_DW];
GO

-- 1. Dim_Date (Role-playing cho arrival_date, booking_date, status_date)
IF OBJECT_ID(N'dw.Dim_Date', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Dim_Date] (
        [date_key]      INT          NOT NULL PRIMARY KEY, -- YYYYMMDD
        [full_date]     DATE         NOT NULL UNIQUE,
        [day_of_month]  TINYINT      NOT NULL,
        [day_of_week]   TINYINT      NOT NULL,
        [day_name]      VARCHAR(20)  NOT NULL,
        [is_weekend]    BIT          NOT NULL,
        [week_of_year]  TINYINT      NOT NULL,
        [month_number]  TINYINT      NOT NULL,
        [month_name]    VARCHAR(20)  NOT NULL,
        [quarter]       TINYINT      NOT NULL,
        [year]          SMALLINT     NOT NULL,
        [season]        VARCHAR(20)  NOT NULL
    );
END
GO

-- 2. Dim_Hotel
IF OBJECT_ID(N'dw.Dim_Hotel', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Dim_Hotel] (
        [hotel_key]     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [hotel_code]    VARCHAR(10)       NOT NULL,
        [hotel_name]    VARCHAR(100)      NOT NULL UNIQUE,
        [city]          VARCHAR(50)       NOT NULL,
        [country]       VARCHAR(50)       NOT NULL
    );
END
GO

-- 3. Dim_Country
IF OBJECT_ID(N'dw.Dim_Country', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Dim_Country] (
        [country_key]   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [country_iso3]  VARCHAR(10)       NOT NULL UNIQUE,
        [country_name]  NVARCHAR(100)     NULL,
        [region]        NVARCHAR(50)      NULL
    );
END
GO

-- 4. Dim_Market_Segment
IF OBJECT_ID(N'dw.Dim_Market_Segment', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Dim_Market_Segment] (
        [market_segment_key]  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [market_segment_name] VARCHAR(100)      NOT NULL UNIQUE,
        [segment_group]       VARCHAR(50)       NOT NULL
    );
END
GO

-- 5. Dim_Distribution_Channel
IF OBJECT_ID(N'dw.Dim_Distribution_Channel', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Dim_Distribution_Channel] (
        [distribution_channel_key]  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [distribution_channel_name] VARCHAR(100)      NOT NULL UNIQUE
    );
END
GO

-- 6. Dim_Room_Type (Role-playing cho reserved_room_type và assigned_room_type)
IF OBJECT_ID(N'dw.Dim_Room_Type', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Dim_Room_Type] (
        [room_type_key]  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [room_type_code] VARCHAR(10)       NOT NULL UNIQUE
    );
END
GO

-- 7. Dim_Booking_Profile (Junk Dimension)
IF OBJECT_ID(N'dw.Dim_Booking_Profile', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Dim_Booking_Profile] (
        [booking_profile_key] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [customer_type]       VARCHAR(50)       NOT NULL,
        [deposit_type]        VARCHAR(50)       NOT NULL,
        [meal_code]           VARCHAR(20)       NOT NULL,
        [meal_description]    VARCHAR(100)      NOT NULL,
        [is_repeated_guest]   BIT               NOT NULL,
        CONSTRAINT [UQ_Dim_Booking_Profile] UNIQUE ([customer_type], [deposit_type], [meal_code], [is_repeated_guest])
    );
END
GO

-- 8. Dim_Reservation_Status
IF OBJECT_ID(N'dw.Dim_Reservation_Status', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Dim_Reservation_Status] (
        [reservation_status_key] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [reservation_status]     VARCHAR(50)       NOT NULL UNIQUE,
        [is_canceled]            BIT               NOT NULL
    );
END
GO

-- 9. Dim_Agent_Company
IF OBJECT_ID(N'dw.Dim_Agent_Company', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Dim_Agent_Company] (
        [agent_company_key] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [agent_id]          VARCHAR(20)       NOT NULL,
        [company_id]        VARCHAR(20)       NOT NULL,
        [has_agent_flag]    BIT               NOT NULL,
        [has_company_flag]  BIT               NOT NULL,
        CONSTRAINT [UQ_Dim_Agent_Company] UNIQUE ([agent_id], [company_id])
    );
END
GO

-- 10. Fact_Hotel_Booking (Transaction Fact Table - Grain: 1 dòng = 1 booking record)
IF OBJECT_ID(N'dw.Fact_Hotel_Booking', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Fact_Hotel_Booking] (
        [booking_sk]                     BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        -- Degenerate Dimensions
        [booking_source_id]              BIGINT               NOT NULL,
        [batch_id]                       INT                  NOT NULL,
        -- Foreign Keys to Dimensions
        [arrival_date_key]               INT                  NOT NULL,
        [booking_date_key]               INT                  NOT NULL,
        [status_date_key]                INT                  NOT NULL,
        [hotel_key]                      INT                  NOT NULL,
        [country_key]                    INT                  NOT NULL,
        [market_segment_key]             INT                  NOT NULL,
        [distribution_channel_key]       INT                  NOT NULL,
        [reserved_room_type_key]         INT                  NOT NULL,
        [assigned_room_type_key]         INT                  NOT NULL,
        [booking_profile_key]            INT                  NOT NULL,
        [reservation_status_key]         INT                  NOT NULL,
        [agent_company_key]              INT                  NOT NULL,
        -- Base Measures
        [lead_time]                      INT                  NOT NULL,
        [stays_in_weekend_nights]        INT                  NOT NULL,
        [stays_in_week_nights]           INT                  NOT NULL,
        [total_nights]                   INT                  NOT NULL,
        [adults]                         INT                  NOT NULL,
        [children]                       INT                  NOT NULL,
        [babies]                         INT                  NOT NULL,
        [total_guests]                   INT                  NOT NULL,
        [adr]                            DECIMAL(12,2)        NOT NULL,
        [estimated_revenue]              DECIMAL(14,2)        NOT NULL,
        [actual_revenue]                 DECIMAL(14,2)        NOT NULL,
        [lost_revenue]                   DECIMAL(14,2)        NOT NULL,
        [booking_changes]                INT                  NOT NULL,
        [days_in_waiting_list]           INT                  NOT NULL,
        [required_car_parking_spaces]    INT                  NOT NULL,
        [total_of_special_requests]      INT                  NOT NULL,
        [previous_cancellations]         INT                  NOT NULL,
        [previous_bookings_not_canceled] INT                  NOT NULL,
        -- Flags
        [is_room_changed]                BIT                  NOT NULL DEFAULT 0,
        [is_adr_outlier]                 BIT                  NOT NULL DEFAULT 0,
        [is_zero_guest]                  BIT                  NOT NULL DEFAULT 0,
        [is_exact_duplicate]             BIT                  NOT NULL DEFAULT 0,
        -- Constraints
        CONSTRAINT [FK_Fact_ArrivalDate]  FOREIGN KEY ([arrival_date_key])         REFERENCES [dw].[Dim_Date]([date_key]),
        CONSTRAINT [FK_Fact_BookingDate]  FOREIGN KEY ([booking_date_key])         REFERENCES [dw].[Dim_Date]([date_key]),
        CONSTRAINT [FK_Fact_StatusDate]   FOREIGN KEY ([status_date_key])          REFERENCES [dw].[Dim_Date]([date_key]),
        CONSTRAINT [FK_Fact_Hotel]        FOREIGN KEY ([hotel_key])                REFERENCES [dw].[Dim_Hotel]([hotel_key]),
        CONSTRAINT [FK_Fact_Country]      FOREIGN KEY ([country_key])              REFERENCES [dw].[Dim_Country]([country_key]),
        CONSTRAINT [FK_Fact_MarketSeg]    FOREIGN KEY ([market_segment_key])       REFERENCES [dw].[Dim_Market_Segment]([market_segment_key]),
        CONSTRAINT [FK_Fact_DistChannel]  FOREIGN KEY ([distribution_channel_key]) REFERENCES [dw].[Dim_Distribution_Channel]([distribution_channel_key]),
        CONSTRAINT [FK_Fact_ReservedRoom] FOREIGN KEY ([reserved_room_type_key])   REFERENCES [dw].[Dim_Room_Type]([room_type_key]),
        CONSTRAINT [FK_Fact_AssignedRoom] FOREIGN KEY ([assigned_room_type_key])   REFERENCES [dw].[Dim_Room_Type]([room_type_key]),
        CONSTRAINT [FK_Fact_Profile]      FOREIGN KEY ([booking_profile_key])      REFERENCES [dw].[Dim_Booking_Profile]([booking_profile_key]),
        CONSTRAINT [FK_Fact_Status]       FOREIGN KEY ([reservation_status_key])   REFERENCES [dw].[Dim_Reservation_Status]([reservation_status_key]),
        CONSTRAINT [FK_Fact_AgentCompany] FOREIGN KEY ([agent_company_key])        REFERENCES [dw].[Dim_Agent_Company]([agent_company_key])
    );
END
GO

-- 11. Fact_Daily_Stay_Snapshot (Bảng Fact phân bổ theo từng đêm lưu trú thực tế)
-- Grain: 1 dòng = 1 đêm lưu trú thực tế của 1 đơn đặt phòng không bị hủy (total_nights > 0)
IF OBJECT_ID(N'dw.Fact_Daily_Stay_Snapshot', N'U') IS NULL
BEGIN
    CREATE TABLE [dw].[Fact_Daily_Stay_Snapshot] (
        [daily_stay_sk]          BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        -- Degenerate Dimensions
        [booking_source_id]      BIGINT               NOT NULL,
        [batch_id]               INT                  NOT NULL,
        -- Foreign Keys to Conformed Dimensions
        [stay_date_key]          INT                  NOT NULL,
        [hotel_key]              INT                  NOT NULL,
        [assigned_room_type_key] INT                  NOT NULL,
        [market_segment_key]     INT                  NOT NULL,
        [booking_profile_key]    INT                  NOT NULL,
        -- Base Measures (Additive theo từng ngày lịch)
        [night_index]            INT                  NOT NULL, -- Đêm thứ 1, 2, ..., N của kỳ nghỉ
        [night_count]            INT                  NOT NULL DEFAULT 1,
        [is_weekend_night]       BIT                  NOT NULL, -- 1 nếu đêm lưu trú rơi vào T7/CN
        [daily_revenue]          DECIMAL(12,2)        NOT NULL, -- Doanh thu phân bổ cho đêm (= adr)
        -- Constraints
        CONSTRAINT [FK_DailyStay_StayDate]     FOREIGN KEY ([stay_date_key])          REFERENCES [dw].[Dim_Date]([date_key]),
        CONSTRAINT [FK_DailyStay_Hotel]        FOREIGN KEY ([hotel_key])              REFERENCES [dw].[Dim_Hotel]([hotel_key]),
        CONSTRAINT [FK_DailyStay_RoomType]     FOREIGN KEY ([assigned_room_type_key]) REFERENCES [dw].[Dim_Room_Type]([room_type_key]),
        CONSTRAINT [FK_DailyStay_MarketSeg]    FOREIGN KEY ([market_segment_key])     REFERENCES [dw].[Dim_Market_Segment]([market_segment_key]),
        CONSTRAINT [FK_DailyStay_Profile]      FOREIGN KEY ([booking_profile_key])    REFERENCES [dw].[Dim_Booking_Profile]([booking_profile_key])
    );
END
GO
