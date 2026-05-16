
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        skan_version as value_field,
        count(*) as n_records

    from `raw`.`skan_postbacks`
    group by skan_version

)

select *
from all_values
where value_field not in (
    '3.0','4.0'
)



  
  
    ) dbt_internal_test