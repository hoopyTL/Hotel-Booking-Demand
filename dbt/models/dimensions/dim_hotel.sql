{{ config(materialized='view', schema='bi', alias='Dim_Hotel') }}

select hotel_key, hotel_code, hotel_name, city, country
from {{ source('warehouse', 'Dim_Hotel') }}
