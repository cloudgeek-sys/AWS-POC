select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select primary_fuel
from "gppa_ci"."main"."fact_power_generation"
where primary_fuel is null



      
    ) dbt_internal_test