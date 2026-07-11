select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select total_capacity_mw
from "gppa_ci"."main"."fact_plant_capacity"
where total_capacity_mw is null



      
    ) dbt_internal_test