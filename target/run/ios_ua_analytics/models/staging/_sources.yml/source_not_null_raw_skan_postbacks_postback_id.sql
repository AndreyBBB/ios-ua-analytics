
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select postback_id
from `raw`.`skan_postbacks`
where postback_id is null



  
  
    ) dbt_internal_test