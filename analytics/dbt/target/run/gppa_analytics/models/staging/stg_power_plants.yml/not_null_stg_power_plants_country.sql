select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select country
from "gppa_ci"."main"."stg_power_plants"
where country is null



      
    ) dbt_internal_test