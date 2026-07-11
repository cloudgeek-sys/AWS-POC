select
  country,
  primary_fuel,
  year,
  total_generation_gwh
from {{ source('gold', 'fact_power_generation') }}
