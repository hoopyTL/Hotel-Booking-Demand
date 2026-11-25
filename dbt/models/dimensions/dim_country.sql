{{ config(materialized='view', schema='bi', alias='Dim_Country') }}

select country_key, country_iso3, country_name, region
from {{ source('warehouse', 'Dim_Country') }}
