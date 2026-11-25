select booking_source_id
from {{ ref('fact_hotel_booking') }}
where adr < 0
   or lead_time < 0
   or total_nights < 0
   or total_guests < 0
   or estimated_revenue < 0
   or actual_revenue < 0
   or lost_revenue < 0
