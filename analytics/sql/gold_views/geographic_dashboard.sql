CREATE OR REPLACE VIEW vw_geographic_plant_distribution AS
SELECT
  country,
  COUNT(*) AS plant_count,
  SUM(capacity_mw) AS total_capacity_mw,
  AVG(capacity_mw) AS avg_capacity_mw
FROM dim_plant
GROUP BY 1;

CREATE OR REPLACE VIEW vw_geographic_generation_density AS
SELECT
  p.country,
  COUNT(DISTINCT p.plant_id) AS plant_count,
  SUM(p.capacity_mw) AS total_capacity_mw,
  SUM(g.total_generation_gwh) AS total_generation_gwh,
  CASE
    WHEN COUNT(DISTINCT p.plant_id) = 0 THEN 0
    ELSE SUM(g.total_generation_gwh) / COUNT(DISTINCT p.plant_id)
  END AS generation_per_plant_gwh
FROM dim_plant p
LEFT JOIN fact_power_generation g
  ON p.country = g.country
 AND p.primary_fuel = g.primary_fuel
GROUP BY 1;

CREATE OR REPLACE VIEW vw_geographic_heatmap_points AS
SELECT
  plant_id,
  plant_name,
  country,
  latitude,
  longitude,
  capacity_mw,
  primary_fuel
FROM dim_plant
WHERE latitude IS NOT NULL
  AND longitude IS NOT NULL;
