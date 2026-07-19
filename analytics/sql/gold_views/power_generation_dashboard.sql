CREATE OR REPLACE VIEW vw_power_generation_country_capacity AS
SELECT
  CAST(country AS varchar) AS country,
  CAST(SUM(total_capacity_mw) AS double) AS total_capacity_mw,
  CAST(SUM(renewable_capacity_mw) AS double) AS renewable_capacity_mw,
  CAST(SUM(total_capacity_mw) - SUM(renewable_capacity_mw) AS double) AS non_renewable_capacity_mw
FROM fact_plant_capacity
GROUP BY 1;

CREATE OR REPLACE VIEW vw_power_generation_fuel_distribution AS
SELECT
  CAST(country AS varchar) AS country,
  CAST(primary_fuel AS varchar) AS primary_fuel,
  CAST(SUM(total_generation_gwh) AS double) AS total_generation_gwh
FROM fact_power_generation
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_power_generation_renewable_trend AS
SELECT
  CAST(g.year AS integer) AS year,
  CAST(g.country AS varchar) AS country,
  CAST(SUM(CASE WHEN f.is_renewable THEN g.total_generation_gwh ELSE 0 END) AS double) AS renewable_generation_gwh,
  CAST(SUM(CASE WHEN NOT f.is_renewable THEN g.total_generation_gwh ELSE 0 END) AS double) AS non_renewable_generation_gwh,
  CAST(CASE
    WHEN SUM(g.total_generation_gwh) = 0 THEN 0
    ELSE SUM(CASE WHEN f.is_renewable THEN g.total_generation_gwh ELSE 0 END) / SUM(g.total_generation_gwh)
  END AS double) AS renewable_generation_ratio
FROM fact_power_generation g
LEFT JOIN dim_fuel_type f
  ON g.primary_fuel = f.primary_fuel
GROUP BY 1,2;

CREATE OR REPLACE VIEW vw_power_generation_global_fuel_dominance AS
WITH global_fuel AS (
  SELECT
    CAST(primary_fuel AS varchar) AS primary_fuel,
    CAST(SUM(total_generation_gwh) AS double) AS total_generation_gwh
  FROM fact_power_generation
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
  CAST(year AS integer) AS year,
  CAST(SUM(total_generation_gwh) AS double) AS total_generation_gwh
FROM fact_power_generation
GROUP BY 1;

CREATE OR REPLACE VIEW vw_power_generation_kpi_summary AS
WITH totals AS (
  SELECT
    CAST(SUM(total_capacity_mw) AS double) AS total_generation_capacity_mw,
    CAST(SUM(renewable_capacity_mw) AS double) AS renewable_capacity_mw
  FROM fact_plant_capacity
),
avg_cap AS (
  SELECT CAST(AVG(capacity_mw) AS double) AS average_plant_capacity_mw
  FROM dim_plant
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
