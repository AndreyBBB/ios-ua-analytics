-- stg_ad_stats: clean and enrich daily ad delivery metrics
-- This is the core table for creative burnout analysis

with source as (
    select * from `raw`.`ad_daily_stats`
),

staged as (
    select
        toDate(stat_date)                                          as stat_date,
        campaign_id,
        creative_id,
        network,
        country,

        -- Raw counters (already integers, just cast for safety)
        toUInt64(impressions)                                      as impressions,
        toUInt64(clicks)                                           as clicks,
        toFloat64(spend_usd)                                       as spend_usd,
        toUInt64(installs)                                         as installs,

        -- Derived metrics (safe division via nullif to avoid divide-by-zero)
        round(clicks / nullif(impressions, 0), 6)                  as ctr,
        round(installs / nullif(clicks, 0), 6)                     as cvr_click_to_install,
        round(spend_usd / nullif(installs, 0), 4)                  as cpi_usd,
        round((spend_usd / nullif(impressions, 0)) * 1000, 4)      as cpm_usd,
        round(spend_usd / nullif(clicks, 0), 4)                    as cpc_usd

    from source
    where
        stat_date is not null
        and campaign_id is not null
        and creative_id is not null
        and spend_usd >= 0
        and impressions >= 0
)

select * from staged