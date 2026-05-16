
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select network
from `raw`.`campaigns`
where network is null



  
  
    ) dbt_internal_test