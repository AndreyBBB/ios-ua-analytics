
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select creative_id
from `raw`.`ad_daily_stats`
where creative_id is null



  
  
    ) dbt_internal_test