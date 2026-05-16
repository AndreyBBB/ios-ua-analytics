
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select stat_date
from `raw`.`ad_daily_stats`
where stat_date is null



  
  
    ) dbt_internal_test