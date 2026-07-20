CREATE OR REPLACE VIEW vw_sustainability_heatmap AS
SELECT
  CAST(plant_id AS varchar) AS plant_id,
  CAST(plant_name AS varchar) AS plant_name,
  CAST(country AS varchar) AS country,
  CAST(latitude AS double) AS latitude,
  CAST(longitude AS double) AS longitude,
  CAST(capacity_mw AS double) AS capacity_mw,
  CAST(primary_fuel AS varchar) AS primary_fuel
FROM dim_plant
WHERE latitude IS NOT NULL
  AND longitude IS NOT NULL
  AND plant_id IS NOT NULL
  AND trim(CAST(plant_id AS varchar)) <> ''
  AND plant_name IS NOT NULL
  AND trim(CAST(plant_name AS varchar)) <> ''
  AND country IS NOT NULL
  AND trim(CAST(country AS varchar)) <> ''
  AND primary_fuel IS NOT NULL
  AND trim(CAST(primary_fuel AS varchar)) <> ''
  AND capacity_mw IS NOT NULL;

CREATE OR REPLACE VIEW vw_sustainability_country_distribution AS
SELECT
  CAST(country AS varchar) AS country,
  CAST(COUNT(*) AS integer) AS plant_count,
  CAST(coalesce(SUM(capacity_mw), 0) AS double) AS total_capacity_mw,
  CAST(AVG(capacity_mw) AS double) AS avg_capacity_mw
FROM dim_plant
WHERE country IS NOT NULL
  AND trim(CAST(country AS varchar)) <> ''
  AND capacity_mw IS NOT NULL
GROUP BY 1;

CREATE OR REPLACE VIEW vw_sustainability_regional_density AS
WITH geo_density AS (
  SELECT
    CAST(continent AS varchar) AS continent,
    CAST(sub_region AS varchar) AS sub_region,
    CAST(coalesce(SUM(total_capacity_mw), 0) AS double) AS total_capacity_mw
  FROM fact_capacity_geo
  WHERE continent IS NOT NULL
    AND trim(CAST(continent AS varchar)) <> ''
    AND sub_region IS NOT NULL
    AND trim(CAST(sub_region AS varchar)) <> ''
    AND total_capacity_mw IS NOT NULL
  GROUP BY 1,2
),
country_fallback AS (
  SELECT
    CAST('Fallback' AS varchar) AS continent,
    CAST(country AS varchar) AS sub_region,
    CAST(coalesce(SUM(capacity_mw), 0) AS double) AS total_capacity_mw
  FROM dim_plant
  WHERE country IS NOT NULL
    AND trim(CAST(country AS varchar)) <> ''
    AND capacity_mw IS NOT NULL
  GROUP BY 2
)
SELECT
  continent,
  sub_region,
  total_capacity_mw
FROM geo_density

UNION ALL

SELECT
  continent,
  sub_region,
  total_capacity_mw
FROM country_fallback
WHERE NOT EXISTS (SELECT 1 FROM geo_density);

CREATE OR REPLACE VIEW vw_sustainability_coal_dependency AS
SELECT
  CAST(continent AS varchar) AS continent,
  CAST(sub_region AS varchar) AS sub_region,
  CAST(coalesce(SUM(CASE WHEN lower(primary_fuel) = 'coal' THEN capacity_mw ELSE 0 END), 0) AS double) AS coal_capacity_mw,
  CAST(coalesce(SUM(capacity_mw), 0) AS double) AS total_capacity_mw,
  CAST(CASE
    WHEN coalesce(SUM(capacity_mw), 0) = 0 THEN 0
    ELSE coalesce(SUM(CASE WHEN lower(primary_fuel) = 'coal' THEN capacity_mw ELSE 0 END), 0) / coalesce(SUM(capacity_mw), 0)
  END AS double) AS coal_capacity_ratio
FROM silver_stg_power_plants
WHERE continent IS NOT NULL
  AND trim(CAST(continent AS varchar)) <> ''
  AND sub_region IS NOT NULL
  AND trim(CAST(sub_region AS varchar)) <> ''
  AND primary_fuel IS NOT NULL
  AND trim(CAST(primary_fuel AS varchar)) <> ''
  AND capacity_mw IS NOT NULL
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_sustainability_clean_energy_growth AS
WITH country_region AS (
  SELECT
    CAST(country AS varchar) AS country,
    CAST(max(continent) AS varchar) AS continent,
    CAST(max(sub_region) AS varchar) AS sub_region
  FROM silver_stg_power_plants
  WHERE country IS NOT NULL
    AND trim(CAST(country AS varchar)) <> ''
    AND continent IS NOT NULL
    AND trim(CAST(continent AS varchar)) <> ''
    AND sub_region IS NOT NULL
    AND trim(CAST(sub_region AS varchar)) <> ''
  GROUP BY 1
)
SELECT
  CAST(try_cast(round(try_cast(g.year AS double)) AS integer) AS varchar) AS year,
  CAST(cr.continent AS varchar) AS continent,
  CAST(cr.sub_region AS varchar) AS sub_region,
  CAST(g.country AS varchar) AS country,
  CAST(coalesce(SUM(CASE WHEN coalesce(f.is_renewable, false) THEN g.total_generation_gwh ELSE 0 END), 0) AS double) AS renewable_generation_gwh,
  CAST(coalesce(SUM(CASE WHEN NOT coalesce(f.is_renewable, false) THEN g.total_generation_gwh ELSE 0 END), 0) AS double) AS non_renewable_generation_gwh
FROM fact_power_generation g
LEFT JOIN dim_fuel_type f
  ON g.primary_fuel = f.primary_fuel
JOIN country_region cr
  ON g.country = cr.country
WHERE g.year IS NOT NULL
  AND g.country IS NOT NULL
  AND trim(CAST(g.country AS varchar)) <> ''
  AND g.primary_fuel IS NOT NULL
  AND trim(CAST(g.primary_fuel AS varchar)) <> ''
  AND g.total_generation_gwh IS NOT NULL
GROUP BY 1,2,3,4;

CREATE OR REPLACE VIEW vw_geographic_plant_distribution AS
SELECT
  CAST(continent AS varchar) AS continent,
  CAST(sub_region AS varchar) AS sub_region,
  CAST(COUNT(*) AS integer) AS plant_count,
  CAST(coalesce(SUM(capacity_mw), 0) AS double) AS total_capacity_mw
FROM silver_stg_power_plants
WHERE continent IS NOT NULL
  AND trim(CAST(continent AS varchar)) <> ''
  AND sub_region IS NOT NULL
  AND trim(CAST(sub_region AS varchar)) <> ''
  AND capacity_mw IS NOT NULL
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_geographic_country_infrastructure_density AS
SELECT
  CAST(country AS varchar) AS country,
  CAST(COUNT(*) AS integer) AS plant_count,
  CAST(coalesce(SUM(capacity_mw), 0) AS double) AS total_capacity_mw,
  CAST(CASE
    WHEN coalesce(SUM(capacity_mw), 0) = 0 THEN 0
    ELSE COUNT(*) / (coalesce(SUM(capacity_mw), 0) / 1000.0)
  END AS double) AS plants_per_1000_mw
FROM silver_stg_power_plants
WHERE country IS NOT NULL
  AND trim(CAST(country AS varchar)) <> ''
  AND capacity_mw IS NOT NULL
GROUP BY 1;
