-- int_creative_daily_metrics
-- One row per (creative_id, stat_date).
-- Adds day_of_life, rolling 7-day CTR, and cumulative spend/installs.
--
-- ClickHouse note: when CREATE TABLE AS SELECT uses table-qualified references
-- (e.g. s.creative_id, c.creative_name), ClickHouse materialises the column with
-- the alias prefix literally in its name ("s.creative_id").  Downstream queries
-- then fail to resolve bare "creative_id".  Fix: explicit AS alias on every
-- table-ref column so the physical table always has clean, unqualified names.

select
    s.stat_date            as stat_date,
    s.campaign_id          as campaign_id,
    s.creative_id          as creative_id,
    s.network              as network,
    s.country              as country,
    c.creative_name        as creative_name,
    c.format               as format,
    c.format_group         as format_group,
    c.is_video             as is_video,
    c.launch_date          as launch_date,
    camp.objective         as objective,
    dateDiff('day', c.launch_date, s.stat_date)     as day_of_life,
    s.impressions          as impressions,
    s.clicks               as clicks,
    s.spend_usd            as spend_usd,
    s.installs             as installs,
    s.ctr                  as ctr,
    s.cvr_click_to_install as cvr_click_to_install,
    s.cpi_usd              as cpi_usd,
    s.cpm_usd              as cpm_usd,
    s.cpc_usd              as cpc_usd,

    -- 7-day rolling average CTR (smooths daily noise for burnout detection)
    avg(s.ctr) over (
        partition by s.creative_id
        order by s.stat_date
        rows between 6 preceding and current row
    )                                               as ctr_7d_avg,

    -- Cumulative peak CTR seen so far in this creative's life
    max(s.ctr) over (
        partition by s.creative_id
        order by s.stat_date
        rows between unbounded preceding and current row
    )                                               as ctr_peak_so_far,

    -- Total cumulative spend on this creative
    sum(s.spend_usd) over (
        partition by s.creative_id
        order by s.stat_date
        rows between unbounded preceding and current row
    )                                               as cumulative_spend_usd,

    -- Total cumulative installs
    sum(s.installs) over (
        partition by s.creative_id
        order by s.stat_date
        rows between unbounded preceding and current row
    )                                               as cumulative_installs

from {{ ref('stg_ad_stats') }} s
inner join {{ ref('stg_creatives') }} c   ON c.creative_id   = s.creative_id
inner join {{ ref('stg_campaigns') }} camp ON camp.campaign_id = s.campaign_id
where s.stat_date >= c.launch_date
