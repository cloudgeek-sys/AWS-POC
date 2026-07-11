CREATE OR REPLACE VIEW vw_power_generation_dashboard AS
SELECT
  country,
  primary_fuel,
  SUM(total_generation_gwh) AS total_generation_gwh,
  SUM(CASE WHEN primary_fuel IN ('Hydro','Solar','Wind','Biomass','Geothermal') THEN total_generation_gwh ELSE 0 END) AS renewable_generation_gwh
FROM fact_power_generation
GROUP BY 1,2;
