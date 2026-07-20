CREATE OR REPLACE VIEW vw_power_generation_country_capacity AS
SELECT
  CAST(country AS varchar) AS country,
  CAST(coalesce(SUM(total_capacity_mw), 0) AS double) AS total_capacity_mw,
  CAST(coalesce(SUM(renewable_capacity_mw), 0) AS double) AS renewable_capacity_mw,
  CAST(coalesce(SUM(total_capacity_mw), 0) - coalesce(SUM(renewable_capacity_mw), 0) AS double) AS non_renewable_capacity_mw
FROM fact_plant_capacity
WHERE country IS NOT NULL
  AND trim(CAST(country AS varchar)) <> ''
  AND total_capacity_mw IS NOT NULL
  AND renewable_capacity_mw IS NOT NULL
GROUP BY 1;

CREATE OR REPLACE VIEW vw_power_generation_fuel_distribution AS
SELECT
  CAST(country AS varchar) AS country,
  CAST(primary_fuel AS varchar) AS primary_fuel,
  CAST(coalesce(SUM(total_generation_gwh), 0) AS double) AS total_generation_gwh
FROM fact_power_generation
WHERE country IS NOT NULL
  AND trim(CAST(country AS varchar)) <> ''
  AND lower(trim(CAST(country AS varchar))) NOT IN ('?', '0', 'unknown', 'unk', 'na', 'n/a', 'null', 'none', '-', '--')
  AND primary_fuel IS NOT NULL
  AND trim(CAST(primary_fuel AS varchar)) <> ''
  AND lower(trim(CAST(primary_fuel AS varchar))) NOT IN ('?', '0', 'unknown', 'unk', 'na', 'n/a', 'null', 'none', '-', '--')
  AND total_generation_gwh IS NOT NULL
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_power_generation_renewable_trend AS
SELECT
  CAST(try_cast(round(try_cast(g.year AS double)) AS integer) AS varchar) AS year,
  CAST(g.country AS varchar) AS country,
  CAST(coalesce(SUM(CASE WHEN coalesce(f.is_renewable, false) THEN g.total_generation_gwh ELSE 0 END), 0) AS double) AS renewable_generation_gwh,
  CAST(coalesce(SUM(CASE WHEN NOT coalesce(f.is_renewable, false) THEN g.total_generation_gwh ELSE 0 END), 0) AS double) AS non_renewable_generation_gwh,
  CAST(CASE
    WHEN coalesce(SUM(g.total_generation_gwh), 0) = 0 THEN 0
    ELSE coalesce(SUM(CASE WHEN coalesce(f.is_renewable, false) THEN g.total_generation_gwh ELSE 0 END), 0) / coalesce(SUM(g.total_generation_gwh), 0)
  END AS double) AS renewable_generation_ratio
FROM fact_power_generation g
LEFT JOIN dim_fuel_type f
  ON g.primary_fuel = f.primary_fuel
WHERE g.year IS NOT NULL
  AND g.country IS NOT NULL
  AND trim(CAST(g.country AS varchar)) <> ''
  AND g.primary_fuel IS NOT NULL
  AND trim(CAST(g.primary_fuel AS varchar)) <> ''
  AND g.total_generation_gwh IS NOT NULL
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_power_generation_global_fuel_dominance AS
WITH global_fuel AS (
  SELECT
    CAST(primary_fuel AS varchar) AS primary_fuel,
    CAST(coalesce(SUM(total_generation_gwh), 0) AS double) AS total_generation_gwh
  FROM fact_power_generation
  WHERE primary_fuel IS NOT NULL
    AND trim(CAST(primary_fuel AS varchar)) <> ''
    AND lower(trim(CAST(primary_fuel AS varchar))) NOT IN ('?', '0', 'unknown', 'unk', 'na', 'n/a', 'null', 'none', '-', '--')
    AND total_generation_gwh IS NOT NULL
  GROUP BY 1
),
global_total AS (
  SELECT CAST(SUM(total_generation_gwh) AS double) AS global_generation_gwh
  FROM global_fuel
)
SELECT
  gf.primary_fuel,
  gf.total_generation_gwh,
  CAST(CASE
    WHEN gt.global_generation_gwh = 0 THEN 0
    ELSE gf.total_generation_gwh / gt.global_generation_gwh
  END AS double) AS fuel_share_ratio
FROM global_fuel gf
CROSS JOIN global_total gt;

CREATE OR REPLACE VIEW vw_power_generation_annual_generation_trends AS
SELECT
  CAST(try_cast(round(try_cast(year AS double)) AS integer) AS varchar) AS year,
  CAST(coalesce(SUM(total_generation_gwh), 0) AS double) AS total_generation_gwh
FROM fact_power_generation
WHERE year IS NOT NULL
  AND total_generation_gwh IS NOT NULL
GROUP BY 1;

CREATE OR REPLACE VIEW vw_power_generation_kpi_summary AS
WITH totals AS (
  SELECT
    CAST(coalesce(SUM(total_capacity_mw), 0) AS double) AS total_generation_capacity_mw,
    CAST(coalesce(SUM(renewable_capacity_mw), 0) AS double) AS renewable_capacity_mw
  FROM fact_plant_capacity
),
avg_cap AS (
  SELECT CAST(coalesce(AVG(capacity_mw), 0) AS double) AS average_plant_capacity_mw
  FROM dim_plant
  WHERE capacity_mw IS NOT NULL
)
SELECT
  t.total_generation_capacity_mw,
  CAST(
    CASE WHEN t.total_generation_capacity_mw = 0 THEN 0
    ELSE t.renewable_capacity_mw / t.total_generation_capacity_mw
    END AS double
  ) AS renewable_energy_ratio,
  a.average_plant_capacity_mw
FROM totals t
CROSS JOIN avg_cap a;
