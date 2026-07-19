CREATE OR REPLACE VIEW vw_plant_operations_largest_plants AS
SELECT
  CAST(plant_id AS varchar) AS plant_id,
  CAST(plant_name AS varchar) AS plant_name,
  CAST(country AS varchar) AS country,
  CAST(primary_fuel AS varchar) AS primary_fuel,
  CAST(capacity_mw AS double) AS capacity_mw,
  CAST(commissioning_year AS integer) AS commissioning_year,
  CAST(latitude AS double) AS latitude,
  CAST(longitude AS double) AS longitude
FROM dim_plant;

CREATE OR REPLACE VIEW vw_plant_operations_aging_infrastructure AS
SELECT
  CAST(country AS varchar) AS country,
  CAST(primary_fuel AS varchar) AS primary_fuel,
  CAST(COUNT(*) AS integer) AS plant_count,
  CAST(AVG(commissioning_year) AS double) AS avg_commissioning_year,
  CAST(SUM(CASE WHEN commissioning_year < year(current_date) - 30 THEN 1 ELSE 0 END) AS integer) AS aging_30_plus_count,
  CAST(SUM(CASE WHEN commissioning_year < year(current_date) - 40 THEN 1 ELSE 0 END) AS integer) AS aging_40_plus_count
FROM dim_plant
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_plant_operations_capacity_utilization AS
WITH generation_by_country_fuel AS (
  SELECT
    country,
    primary_fuel,
    year,
    SUM(total_generation_gwh) AS total_generation_gwh
  FROM fact_power_generation
  GROUP BY 1,2,3
),
capacity_by_country_fuel AS (
  SELECT
    country,
    primary_fuel,
    SUM(total_capacity_mw) AS total_capacity_mw
  FROM fact_plant_capacity
  GROUP BY 1,2
)
SELECT
  CAST(g.year AS integer) AS year,
  CAST(g.country AS varchar) AS country,
  CAST(g.primary_fuel AS varchar) AS primary_fuel,
  CAST(c.total_capacity_mw AS double) AS total_capacity_mw,
  CAST(g.total_generation_gwh AS double) AS total_generation_gwh,
  CAST((c.total_capacity_mw * 8.76) AS double) AS theoretical_max_generation_gwh,
  CAST(CASE
    WHEN c.total_capacity_mw <= 0 THEN 0
    ELSE g.total_generation_gwh / (c.total_capacity_mw * 8.76)
  END AS double) AS utilization_ratio
FROM generation_by_country_fuel g
JOIN capacity_by_country_fuel c
  ON g.country = c.country
 AND g.primary_fuel = c.primary_fuel;

CREATE OR REPLACE VIEW vw_plant_operations_underutilized_plants AS
SELECT
  CAST(plant_id AS varchar) AS plant_id,
  CAST(plant_name AS varchar) AS plant_name,
  CAST(country AS varchar) AS country,
  CAST(primary_fuel AS varchar) AS primary_fuel,
  CAST(capacity_mw AS double) AS capacity_mw,
  CAST(estimated_generation_gwh AS double) AS estimated_generation_gwh,
  CAST(capacity_mw * 8.76 AS double) AS theoretical_generation_gwh,
  CAST(CASE
    WHEN capacity_mw <= 0 THEN 0
    ELSE estimated_generation_gwh / (capacity_mw * 8.76)
  END AS double) AS utilization_ratio
FROM silver_stg_power_plants
WHERE capacity_mw IS NOT NULL
  AND estimated_generation_gwh IS NOT NULL
  AND capacity_mw > 0
  AND (estimated_generation_gwh / (capacity_mw * 8.76)) < 0.40;

CREATE OR REPLACE VIEW vw_plant_operations_aging_by_region AS
SELECT
  CAST(continent AS varchar) AS continent,
  CAST(sub_region AS varchar) AS sub_region,
  CAST(COUNT(*) AS integer) AS plant_count,
  CAST(AVG(commissioning_year) AS double) AS avg_commissioning_year,
  CAST(SUM(CASE WHEN commissioning_year < year(current_date) - 30 THEN 1 ELSE 0 END) AS integer) AS aging_30_plus_count,
  CAST(SUM(CASE WHEN commissioning_year < year(current_date) - 40 THEN 1 ELSE 0 END) AS integer) AS aging_40_plus_count
FROM silver_stg_power_plants
GROUP BY 1,2;
