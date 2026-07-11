select
  country,
  primary_fuel,
  total_capacity_mw,
  renewable_capacity_mw
from {{ source('gold', 'fact_plant_capacity') }}
