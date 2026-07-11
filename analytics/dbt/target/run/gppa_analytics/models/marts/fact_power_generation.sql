
  
    
    

    create  table
      "gppa_ci"."main"."fact_power_generation__dbt_tmp"
  
    as (
      select
  country,
  primary_fuel,
  year,
  total_generation_gwh
from "gppa_ci"."gppa_gold"."fact_power_generation"
    );
  
  