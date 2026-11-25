{{ config(materialized='view', schema='bi', alias='Dim_Reservation_Status') }}

select reservation_status_key, reservation_status, is_canceled
from {{ source('warehouse', 'Dim_Reservation_Status') }}
