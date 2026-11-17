-- ============================================================================
-- 01_init_databases_and_schemas.sql
-- Khởi tạo Database và các Schema: meta (Metadata), stg (Staging), dw (DDS)
-- ============================================================================

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'HotelBooking_DW')
BEGIN
    CREATE DATABASE [HotelBooking_DW];
END
GO

USE [HotelBooking_DW];
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'meta')
    EXEC('CREATE SCHEMA [meta]');
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'stg')
    EXEC('CREATE SCHEMA [stg]');
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'dw')
    EXEC('CREATE SCHEMA [dw]');
GO
