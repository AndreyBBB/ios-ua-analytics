
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  -- Custom data test: burnout_score must be between 0 and 1.
-- Any row returned = test failure.

select
    creative_id,
    stat_date,
    burnout_score
from `marts_marts`.`mart_creative_burnout`
where burnout_score < 0 or burnout_score > 1
  
  
    ) dbt_internal_test