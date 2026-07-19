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
  AND longitude IS NOT NULL;

CREATE OR REPLACE VIEW vw_sustainability_country_distribution AS
SELECT
  CAST(country AS varchar) AS country,
  CAST(COUNT(*) AS integer) AS plant_count,
  CAST(SUM(capacity_mw) AS double) AS total_capacity_mw,
  CAST(AVG(capacity_mw) AS double) AS avg_capacity_mw
FROM dim_plant
GROUP BY 1;

CREATE OR REPLACE VIEW vw_sustainability_regional_density AS
WITH geo_density AS (
  SELECT
    CAST(continent AS varchar) AS continent,
    CAST(sub_region AS varchar) AS sub_region,
    CAST(SUM(total_capacity_mw) AS double) AS total_capacity_mw
  FROM fact_capacity_geo
  GROUP BY 1,2
),
country_fallback AS (
  SELECT
    CAST('Unknown' AS varchar) AS continent,
    CAST(country AS varchar) AS sub_region,
    CAST(SUM(capacity_mw) AS double) AS total_capacity_mw
  FROM dim_plant
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
  CAST(SUM(CASE WHEN lower(primary_fuel) = 'coal' THEN capacity_mw ELSE 0 END) AS double) AS coal_capacity_mw,
  CAST(SUM(capacity_mw) AS double) AS total_capacity_mw,
  CAST(CASE
    WHEN SUM(capacity_mw) = 0 THEN 0
    ELSE SUM(CASE WHEN lower(primary_fuel) = 'coal' THEN capacity_mw ELSE 0 END) / SUM(capacity_mw)
  END AS double) AS coal_capacity_ratio
FROM silver_stg_power_plants
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_sustainability_clean_energy_growth AS
WITH country_region AS (
  SELECT
    CAST(country AS varchar) AS country,
    CAST(max(continent) AS varchar) AS continent,
    CAST(max(sub_region) AS varchar) AS sub_region
  FROM silver_stg_power_plants
  GROUP BY 1
)
SELECT
  CAST(g.year AS integer) AS year,
  CAST(coalesce(cr.continent, 'Unknown') AS varchar) AS continent,
  CAST(coalesce(cr.sub_region, 'Unknown') AS varchar) AS sub_region,
  CAST(g.country AS varchar) AS country,
  CAST(SUM(CASE WHEN f.is_renewable THEN g.total_generation_gwh ELSE 0 END) AS double) AS renewable_generation_gwh,
  CAST(SUM(CASE WHEN NOT f.is_renewable THEN g.total_generation_gwh ELSE 0 END) AS double) AS non_renewable_generation_gwh
FROM fact_power_generation g
LEFT JOIN dim_fuel_type f
  ON g.primary_fuel = f.primary_fuel
LEFT JOIN country_region cr
  ON g.country = cr.country
GROUP BY 1,2,3,4;

CREATE OR REPLACE VIEW vw_geographic_plant_distribution AS
SELECT
  CAST(continent AS varchar) AS continent,
  CAST(sub_region AS varchar) AS sub_region,
  CAST(COUNT(*) AS integer) AS plant_count,
  CAST(SUM(capacity_mw) AS double) AS total_capacity_mw
FROM silver_stg_power_plants
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_geographic_country_infrastructure_density AS
SELECT
  CAST(country AS varchar) AS country,
  CAST(COUNT(*) AS integer) AS plant_count,
  CAST(SUM(capacity_mw) AS double) AS total_capacity_mw,
  CAST(CASE
    WHEN SUM(capacity_mw) = 0 THEN 0
    ELSE COUNT(*) / (SUM(capacity_mw) / 1000.0)
  END AS double) AS plants_per_1000_mw
FROM silver_stg_power_plants
GROUP BY 1;
