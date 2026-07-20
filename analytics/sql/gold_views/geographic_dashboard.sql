CREATE OR REPLACE VIEW vw_geographic_plant_distribution AS
SELECT
  country,
  COUNT(*) AS plant_count,
  coalesce(SUM(capacity_mw), 0) AS total_capacity_mw,
  AVG(capacity_mw) AS avg_capacity_mw
FROM dim_plant
WHERE country IS NOT NULL
  AND trim(CAST(country AS varchar)) <> ''
  AND capacity_mw IS NOT NULL
GROUP BY 1;

CREATE OR REPLACE VIEW vw_geographic_generation_density AS
SELECT
  p.country AS country,
  COUNT(DISTINCT p.plant_id) AS plant_count,
  coalesce(SUM(p.capacity_mw), 0) AS total_capacity_mw,
  coalesce(SUM(g.total_generation_gwh), 0) AS total_generation_gwh,
  CASE
    WHEN COUNT(DISTINCT p.plant_id) = 0 THEN 0
    ELSE coalesce(SUM(g.total_generation_gwh), 0) / COUNT(DISTINCT p.plant_id)
  END AS generation_per_plant_gwh
FROM dim_plant p
LEFT JOIN fact_power_generation g
  ON p.country = g.country
 AND p.primary_fuel = g.primary_fuel
WHERE p.country IS NOT NULL
  AND trim(CAST(p.country AS varchar)) <> ''
  AND p.plant_id IS NOT NULL
  AND trim(CAST(p.plant_id AS varchar)) <> ''
  AND p.capacity_mw IS NOT NULL
  AND p.primary_fuel IS NOT NULL
  AND trim(CAST(p.primary_fuel AS varchar)) <> ''
  AND g.total_generation_gwh IS NOT NULL
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
  AND longitude IS NOT NULL
  AND plant_id IS NOT NULL
  AND trim(CAST(plant_id AS varchar)) <> ''
  AND plant_name IS NOT NULL
  AND trim(CAST(plant_name AS varchar)) <> ''
  AND country IS NOT NULL
  AND trim(CAST(country AS varchar)) <> ''
  AND capacity_mw IS NOT NULL
  AND primary_fuel IS NOT NULL
  AND trim(CAST(primary_fuel AS varchar)) <> '';
