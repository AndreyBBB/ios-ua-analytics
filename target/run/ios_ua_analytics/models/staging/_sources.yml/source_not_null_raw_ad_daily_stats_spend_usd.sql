
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select spend_usd
from `raw`.`ad_daily_stats`
where spend_usd is null



  
  
    ) dbt_internal_test