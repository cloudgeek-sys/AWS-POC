select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select capacity_mw
from "gppa_ci"."main"."stg_power_plants"
where capacity_mw is null



      
    ) dbt_internal_test