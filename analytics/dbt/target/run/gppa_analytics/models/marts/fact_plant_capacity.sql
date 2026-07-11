
  
    
    

    create  table
      "gppa_ci"."main"."fact_plant_capacity__dbt_tmp"
  
    as (
      select
  country,
  primary_fuel,
  total_capacity_mw,
  renewable_capacity_mw
from "gppa_ci"."gppa_gold"."fact_plant_capacity"
    );
  
  