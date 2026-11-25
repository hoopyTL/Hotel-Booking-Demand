{{ config(materialized='view', schema='bi', alias='Dim_Distribution_Channel') }}

select distribution_channel_key, distribution_channel_name
from {{ source('warehouse', 'Dim_Distribution_Channel') }}
