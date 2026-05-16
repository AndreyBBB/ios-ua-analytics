
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        format as value_field,
        count(*) as n_records

    from `raw`.`creatives`
    group by format

)

select *
from all_values
where value_field not in (
    'video_15s','video_30s','static_image','carousel'
)



  
  
    ) dbt_internal_test