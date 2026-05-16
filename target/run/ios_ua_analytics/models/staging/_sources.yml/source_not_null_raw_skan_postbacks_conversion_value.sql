
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select conversion_value
from `raw`.`skan_postbacks`
where conversion_value is null



  
  
    ) dbt_internal_test