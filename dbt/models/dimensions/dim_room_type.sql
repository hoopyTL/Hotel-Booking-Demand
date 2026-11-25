{{ config(materialized='view', schema='bi', alias='Dim_Room_Type') }}

select room_type_key, room_type_code
from {{ source('warehouse', 'Dim_Room_Type') }}
