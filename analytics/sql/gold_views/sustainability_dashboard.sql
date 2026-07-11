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
