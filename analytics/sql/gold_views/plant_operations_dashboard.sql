CREATE OR REPLACE VIEW vw_plant_operations_dashboard AS
SELECT
  p.plant_id,
  p.plant_name,
  p.country,
  p.primary_fuel,
  p.capacity_mw AS plant_capacity_mw,
  p.commissioning_year,
  c.total_capacity_mw AS country_fuel_capacity_mw
FROM dim_plant p
JOIN fact_plant_capacity c
  ON p.country = c.country
 AND p.primary_fuel = c.primary_fuel;
