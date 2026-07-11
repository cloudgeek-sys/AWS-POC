# Superset Dataset Contract

## Required datasets

- dim_plant
- dim_country
- dim_fuel_type
- dim_time
- fact_plant_capacity
- fact_power_generation
- silver_quality_report

## Security model

- Role: data_engineer -> full dataset access
- Role: analyst -> gold datasets + monitoring views
- Role: dashboard_consumer -> curated views only

## Refresh policy

- Gold datasets refreshed once daily
- Monitoring views refreshed every 15 minutes
