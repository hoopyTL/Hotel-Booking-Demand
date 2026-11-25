select
    staging.staging_row_id as booking_source_id
from {{ ref('stg_hotel_bookings') }} as staging
left join {{ ref('fact_hotel_booking') }} as booking
    on booking.booking_source_id = staging.staging_row_id
where booking.booking_source_id is null

union all

select
    booking.booking_source_id
from {{ ref('fact_hotel_booking') }} as booking
left join {{ ref('stg_hotel_bookings') }} as staging
    on staging.staging_row_id = booking.booking_source_id
where staging.staging_row_id is null
