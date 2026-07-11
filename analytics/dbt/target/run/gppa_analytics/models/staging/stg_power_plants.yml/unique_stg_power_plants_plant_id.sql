select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    

select
    plant_id as unique_field,
    count(*) as n_records

from "gppa_ci"."main"."stg_power_plants"
where plant_id is not null
group by plant_id
having count(*) > 1



      
    ) dbt_internal_test