{{ config(materialized='view', schema='bi', alias='Dim_Date') }}

select
    date_key,
    full_date,
    day_of_month,
    day_of_week,
    day_name,
    is_weekend,
    week_of_year,
    month_number,
    month_name,
    quarter,
    year,
    season
from {{ source('warehouse', 'Dim_Date') }}
