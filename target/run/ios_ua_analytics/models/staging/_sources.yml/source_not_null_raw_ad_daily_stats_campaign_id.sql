
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select campaign_id
from `raw`.`ad_daily_stats`
where campaign_id is null



  
  
    ) dbt_internal_test