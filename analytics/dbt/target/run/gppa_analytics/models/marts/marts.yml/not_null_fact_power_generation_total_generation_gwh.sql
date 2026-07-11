select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select total_generation_gwh
from "gppa_ci"."main"."fact_power_generation"
where total_generation_gwh is null



      
    ) dbt_internal_test