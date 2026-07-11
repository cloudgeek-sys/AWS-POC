
    
    

select
    plant_id as unique_field,
    count(*) as n_records

from "gppa_ci"."main"."stg_power_plants"
where plant_id is not null
group by plant_id
having count(*) > 1


