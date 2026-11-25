{{ config(materialized='view', schema='bi', alias='Dim_Booking_Profile') }}

select
    booking_profile_key,
    customer_type,
    deposit_type,
    meal_code,
    meal_description,
    is_repeated_guest
from {{ source('warehouse', 'Dim_Booking_Profile') }}
