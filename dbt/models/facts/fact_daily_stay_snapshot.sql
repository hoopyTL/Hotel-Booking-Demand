{{ config(materialized='table', schema='bi', alias='Fact_Daily_Stay_Snapshot') }}

with numbers as (
    select 0 as n
    union all
    select n + 1
    from numbers
    where n < 100
)
select
    row_number() over (
        order by booking.booking_source_id, numbers.n
    ) as daily_stay_sk,
    booking.booking_source_id,
    booking.batch_id,
    stay_date.date_key as stay_date_key,
    booking.hotel_key,
    booking.assigned_room_type_key,
    booking.market_segment_key,
    booking.booking_profile_key,
    numbers.n + 1 as night_index,
    1 as night_count,
    stay_date.is_weekend as is_weekend_night,
    booking.adr as daily_revenue
from {{ ref('fact_hotel_booking') }} as booking
inner join {{ ref('dim_reservation_status') }} as status
    on status.reservation_status_key = booking.reservation_status_key
inner join {{ ref('dim_date') }} as arrival_date
    on arrival_date.date_key = booking.arrival_date_key
inner join numbers
    on numbers.n < booking.total_nights
inner join {{ ref('dim_date') }} as stay_date
    on stay_date.full_date = dateadd(day, numbers.n, arrival_date.full_date)
where status.is_canceled = 0
  and booking.total_nights > 0
option (maxrecursion 0)
