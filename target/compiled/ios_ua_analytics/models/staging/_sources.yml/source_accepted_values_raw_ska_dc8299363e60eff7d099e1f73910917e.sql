
    
    

with all_values as (

    select
        privacy_threshold as value_field,
        count(*) as n_records

    from `raw`.`skan_postbacks`
    group by privacy_threshold

)

select *
from all_values
where value_field not in (
    'none','low','medium'
)


