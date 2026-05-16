
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select daily_budget
from `raw`.`campaigns`
where daily_budget is null



  
  
    ) dbt_internal_test