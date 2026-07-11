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
