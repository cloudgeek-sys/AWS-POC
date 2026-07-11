select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select plant_id
from "gppa_ci"."main"."stg_power_plants"
where plant_id is null



      
    ) dbt_internal_test