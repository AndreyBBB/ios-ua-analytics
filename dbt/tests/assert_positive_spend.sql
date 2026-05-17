-- Custom data test: no negative spend in raw ad stats.
-- dbt tests pass when the query returns 0 rows.
-- Any row returned = test failure.

select
    stat_date,
    campaign_id,
    creative_id,
    spend_usd
from {{ ref('stg_ad_stats') }}
where spend_usd < 0
