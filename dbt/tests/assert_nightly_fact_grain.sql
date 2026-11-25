with nightly_totals as (
    select
        booking_source_id,
        count_big(*) as nights,
        sum(daily_revenue) as revenue
    from {{ ref('fact_daily_stay_snapshot') }}
    group by booking_source_id
)
select
    booking.booking_source_id,
    booking.total_nights,
    booking.actual_revenue,
    coalesce(nightly_totals.nights, 0) as allocated_nights,
    coalesce(nightly_totals.revenue, 0) as allocated_revenue
from {{ ref('fact_hotel_booking') }} as booking
inner join {{ ref('dim_reservation_status') }} as status
    on status.reservation_status_key = booking.reservation_status_key
left join nightly_totals
    on nightly_totals.booking_source_id = booking.booking_source_id
where coalesce(nightly_totals.nights, 0) <>
      case when status.is_canceled = 0 then booking.total_nights else 0 end
   or coalesce(nightly_totals.revenue, 0) <> booking.actual_revenue
