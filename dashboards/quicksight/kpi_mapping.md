# QuickSight KPI Mapping

Selected BI platform: AWS QuickSight

This project uses QuickSight only. Superset artifacts are not part of the active BI scope.

Implementation checklist:

- docs/runbooks/quicksight_visual_implementation_checklist.md

## Dashboard evidence PDFs

- dashboards/Power-Generation-Dashboard.pdf
- dashboards/Plant-Operations-Dashboard.pdf
- dashboards/Sustainability-Dashboard.pdf
- dashboards/Monitoring-Dashboard.pdf

## Power Generation Dashboard

- Country capacity: vw_power_generation_country_capacity
- Fuel distribution: vw_power_generation_fuel_distribution
- Renewable trends: vw_power_generation_renewable_trend
- Annual generation trends: vw_power_generation_annual_generation_trends
- KPI summary (total generation capacity, renewable ratio, average plant capacity): vw_power_generation_kpi_summary

## Mandatory KPI Metrics

- Total generation capacity: vw_power_generation_kpi_summary.total_generation_capacity_mw
- Renewable energy ratio: vw_power_generation_kpi_summary.renewable_energy_ratio
- Average plant capacity: vw_power_generation_kpi_summary.average_plant_capacity_mw
- Country-wise fuel distribution: vw_power_generation_fuel_distribution
- Annual generation trends: vw_power_generation_annual_generation_trends

## Plant Dashboard

- Largest plants: vw_plant_operations_largest_plants
- Aging plants: vw_plant_operations_aging_infrastructure
- Utilization: vw_plant_operations_capacity_utilization

## Sustainability Dashboard

- Heatmap: vw_sustainability_heatmap
- Country distribution: vw_sustainability_country_distribution
- Regional density: vw_sustainability_regional_density
- Coal dependency by region: vw_sustainability_coal_dependency
- Clean energy growth by year/region/country: vw_sustainability_clean_energy_growth

## Geographic Analytics

- Plant distribution by region: vw_geographic_plant_distribution
- Country infrastructure density: vw_geographic_country_infrastructure_density
- Regional generation/capacity comparison: vw_sustainability_regional_density

## Monitoring Dashboard

- Pipeline freshness: vw_monitoring_pipeline_freshness
- Failed jobs: vw_monitoring_failed_jobs
- Data quality: vw_monitoring_data_quality
- Latency: vw_monitoring_latency
- Duplicate plant detection: vw_monitoring_duplicate_plants
- Missing or inconsistent generation records: vw_monitoring_missing_or_inconsistent_generation

## Required Dashboard Views (Mandatory)

### Power Generation Dashboard (Mandatory)

- Country-wise generation capacity: vw_power_generation_country_capacity
- Fuel type distribution: vw_power_generation_fuel_distribution
- Renewable vs non-renewable trends: vw_power_generation_renewable_trend

### Plant Operations Dashboard (Mandatory)

- Largest power plants: vw_plant_operations_largest_plants
- Plant aging analysis: vw_plant_operations_aging_infrastructure
- Capacity utilization indicators: vw_plant_operations_capacity_utilization

### Sustainability Dashboard (Mandatory)

- Renewable adoption trends: vw_sustainability_clean_energy_growth
- Coal dependency analysis: vw_sustainability_coal_dependency
- Regional clean energy comparison: vw_sustainability_clean_energy_growth

### Geographic Dashboard (Mandatory)

- Global power plant heatmaps: vw_sustainability_heatmap
- Country-wise infrastructure distribution: vw_geographic_country_infrastructure_density
- Regional generation density: vw_geographic_generation_density

### Operational Monitoring Dashboard (Mandatory)

- Pipeline freshness: vw_monitoring_pipeline_freshness
- Failed ingestion jobs: vw_monitoring_failed_jobs
- Data quality alerts: vw_monitoring_data_quality
- Processing latency: vw_monitoring_latency

## Goal-to-View Coverage

### Power Generation Analytics

- Highest power capacity countries: vw_power_generation_country_capacity
- Globally dominant fuel sources: vw_power_generation_global_fuel_dominance
- Renewable vs non-renewable trends: vw_power_generation_renewable_trend

### Plant Operations Analytics

- Highest generation-capacity plants: vw_plant_operations_largest_plants
- Aging infrastructure by region: vw_plant_operations_aging_by_region
- Below-expected utilization plants: vw_plant_operations_underutilized_plants

### Sustainability & Environmental Insights

- Coal-heavy regions: vw_sustainability_coal_dependency
- Renewable adoption trend by country: vw_sustainability_clean_energy_growth
- Clean energy growth by year/region: vw_sustainability_clean_energy_growth

### Geographic Analytics Coverage

- Distribution of plants by region: vw_geographic_plant_distribution
- Country-wise infrastructure density: vw_geographic_country_infrastructure_density
- Regional capacity comparison: vw_sustainability_regional_density

### Operational Monitoring

- Missing/inconsistent generation records: vw_monitoring_missing_or_inconsistent_generation
- Duplicate plant entries: vw_monitoring_duplicate_plants
- Ingestion freshness and latency: vw_monitoring_pipeline_freshness, vw_monitoring_latency
