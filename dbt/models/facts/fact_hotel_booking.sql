{{ config(materialized='table', schema='bi', alias='Fact_Hotel_Booking') }}

select
    c.staging_row_id as booking_sk,
    c.staging_row_id as booking_source_id,
    c.batch_id,
    arrival_date.date_key as arrival_date_key,
    booking_date.date_key as booking_date_key,
    status_date.date_key as status_date_key,
    hotel.hotel_key,
    country.country_key,
    market_segment.market_segment_key,
    distribution_channel.distribution_channel_key,
    reserved_room.room_type_key as reserved_room_type_key,
    assigned_room.room_type_key as assigned_room_type_key,
    booking_profile.booking_profile_key,
    reservation_status.reservation_status_key,
    agent_company.agent_company_key,
    c.lead_time,
    c.stays_in_weekend_nights,
    c.stays_in_week_nights,
    c.total_nights,
    c.adults,
    c.children,
    c.babies,
    c.total_guests,
    c.adr,
    c.estimated_revenue,
    c.actual_revenue,
    c.lost_revenue,
    c.booking_changes,
    c.days_in_waiting_list,
    c.required_car_parking_spaces,
    c.total_of_special_requests,
    c.previous_cancellations,
    c.previous_bookings_not_canceled,
    c.is_room_changed,
    c.is_adr_outlier,
    c.is_zero_guest,
    c.is_exact_duplicate
from {{ ref('stg_hotel_bookings') }} as c
inner join {{ ref('dim_date') }} as arrival_date
    on arrival_date.full_date = c.arrival_date
inner join {{ ref('dim_date') }} as booking_date
    on booking_date.full_date = c.booking_date
inner join {{ ref('dim_date') }} as status_date
    on status_date.full_date = c.reservation_status_date
inner join {{ ref('dim_hotel') }} as hotel
    on hotel.hotel_name = c.hotel
inner join {{ ref('dim_country') }} as country
    on country.country_iso3 = c.country
inner join {{ ref('dim_market_segment') }} as market_segment
    on market_segment.market_segment_name = c.market_segment
inner join {{ ref('dim_distribution_channel') }} as distribution_channel
    on distribution_channel.distribution_channel_name = c.distribution_channel
inner join {{ ref('dim_room_type') }} as reserved_room
    on reserved_room.room_type_code = c.reserved_room_type
inner join {{ ref('dim_room_type') }} as assigned_room
    on assigned_room.room_type_code = c.assigned_room_type
inner join {{ ref('dim_booking_profile') }} as booking_profile
    on booking_profile.customer_type = c.customer_type
   and booking_profile.deposit_type = c.deposit_type
   and booking_profile.meal_code = c.meal
   and booking_profile.is_repeated_guest = c.is_repeated_guest
inner join {{ ref('dim_reservation_status') }} as reservation_status
    on reservation_status.reservation_status = c.reservation_status
   and reservation_status.is_canceled = c.is_canceled
inner join {{ ref('dim_agent_company') }} as agent_company
    on agent_company.agent_id = c.agent_id
   and agent_company.company_id = c.company_id
