# QuickSight KPI Mapping

## Power Generation Dashboard

- Country-wise generation capacity: fact_plant_capacity.total_capacity_mw by country
- Fuel type distribution: fact_plant_capacity.total_capacity_mw by primary_fuel
- Renewable vs non-renewable trends: fact_power_generation with renewable classification

## Plant Operations Dashboard

- Largest power plants: dim_plant joined with fact_plant_capacity
- Plant aging analysis: current_year - commissioning_year
- Capacity utilization indicators: estimated_generation_gwh / capacity_mw (proxy)

## Sustainability Dashboard

- Renewable adoption trends: renewable_generation_gwh / total_generation_gwh
- Coal dependency analysis: capacity share where primary_fuel='Coal'
- Regional clean energy comparison: grouped by country and region

## Geographic Dashboard

- Heatmap: latitude/longitude from dim_plant
- Infrastructure distribution: plant count by country
- Generation density: total_capacity_mw by country

## Operational Monitoring Dashboard

- Pipeline freshness: freshness_lag_hours metric
- Failed jobs: dq_failure_count and orchestration failures
- Data quality alerts: malformed_rows trend
- Processing latency: end_to_end_duration_minutes metric
