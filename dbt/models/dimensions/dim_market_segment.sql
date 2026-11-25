{{ config(materialized='view', schema='bi', alias='Dim_Market_Segment') }}

select market_segment_key, market_segment_name, segment_group
from {{ source('warehouse', 'Dim_Market_Segment') }}
