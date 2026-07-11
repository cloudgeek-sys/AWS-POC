select
  plant_id,
  plant_name,
  country,
  capacity_mw,
  primary_fuel,
  commissioning_year,
  latitude,
  longitude,
  substr(owner, 1, 3) || '***' as owner_masked,
  event_year,
  event_month
from {{ source('silver', 'stg_power_plants') }}
