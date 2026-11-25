{{ config(materialized='view', schema='bi', alias='Dim_Agent_Company') }}

select
    agent_company_key,
    agent_id,
    company_id,
    has_agent_flag,
    has_company_flag
from {{ source('warehouse', 'Dim_Agent_Company') }}
