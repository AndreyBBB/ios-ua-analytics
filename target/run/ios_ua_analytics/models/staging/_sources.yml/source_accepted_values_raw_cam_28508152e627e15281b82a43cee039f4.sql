
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        network as value_field,
        count(*) as n_records

    from `raw`.`campaigns`
    group by network

)

select *
from all_values
where value_field not in (
    'Meta','Google_UAC','Apple_Search_Ads','TikTok','Snap'
)



  
  
    ) dbt_internal_test