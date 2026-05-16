
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  -- Custom data test: no negative spend in raw ad stats.
-- dbt tests pass when the query returns 0 rows.
-- Any row returned = test failure.

select
    stat_date,
    campaign_id,
    creative_id,
    spend_usd
from `marts_staging`.`stg_ad_stats`
where spend_usd < 0
  
  
    ) dbt_internal_test