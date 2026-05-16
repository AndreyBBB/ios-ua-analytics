-- mart_creative_burnout  ★ HEADLINE INSIGHT
-- ─────────────────────────────────────────────────────────────────────────────
-- One row per (creative_id, stat_date).
-- Calculates the burnout score and lifecycle stage for every active creative.
--
-- Key outputs for Power BI:
--   burnout_score                  : 0→1, where 1 = fully burnt (CTR at 70% of peak or below)
--   lifecycle_stage                : 'warming_up' | 'peak' | 'declining' | 'burnt'
--   days_to_burnout                : how many days until the creative crossed the threshold
--   wasted_spend_usd               : spend that continued after burnout threshold
--
-- Architecture note:
--   creative_peaks and burnout_events are materialized as separate intermediate
--   models (int_creative_peaks, int_burnout_events) to avoid ClickHouse
--   multi-level CTE scope errors. This mart JOINs real tables only.
--
-- INCREMENTAL MODEL: in production, only processes new dates each run.
-- ─────────────────────────────────────────────────────────────────────────────



-- daily: simple filter on the metrics intermediate — no JOIN, no window functions here
-- (ClickHouse handles a single-level CTE with no JOINs without scope issues)
with daily as (
    select * from `marts_intermediate`.`int_creative_daily_metrics`
    where impressions >= 500

    
)

select
    d.stat_date              as stat_date,
    d.creative_id            as creative_id,
    d.campaign_id            as campaign_id,
    d.network                as network,
    d.country                as country,
    d.creative_name          as creative_name,
    d.format                 as format,
    d.format_group           as format_group,
    d.is_video               as is_video,
    d.launch_date            as launch_date,
    d.day_of_life            as day_of_life,

    -- Raw metrics
    d.impressions            as impressions,
    d.clicks                 as clicks,
    d.spend_usd              as spend_usd,
    d.installs               as installs,
    d.ctr                    as ctr,
    d.ctr_7d_avg             as ctr_7d_avg,
    d.cpi_usd                as cpi_usd,
    d.cumulative_spend_usd   as cumulative_spend_usd,
    d.cumulative_installs    as cumulative_installs,

    -- Peak reference (from materialized int_creative_peaks)
    p.absolute_peak_ctr      as absolute_peak_ctr,
    p.peak_day_of_life       as peak_day_of_life,

    -- Burnout reference (from materialized int_burnout_events)
    be.burnout_date          as burnout_date,
    be.burnout_day_of_life   as burnout_day_of_life,

    -- ── BURNOUT SCORE (0→1) ──────────────────────────────────────────────────
    -- 0 = performing at peak; 1 = fully burnt out
    -- Formula: 1 - (current_7d_ctr / peak_ctr), clipped to [0, 1]
    round(
        greatest(0.0,
            1.0 - (d.ctr_7d_avg / nullif(p.absolute_peak_ctr, 0))
        ),
        4
    )                                                            as burnout_score,

    -- ── LIFECYCLE STAGE ──────────────────────────────────────────────────────
    case
        when d.day_of_life <= p.peak_day_of_life
            then 'warming_up'
        when be.burnout_date is null
            or d.stat_date < be.burnout_date
            then 'peak'
        when d.ctr_7d_avg >= (p.absolute_peak_ctr * 0.7)
            then 'declining'
        else 'burnt'
    end                                                          as lifecycle_stage,

    -- ── IS PAST BURNOUT THRESHOLD? ───────────────────────────────────────────
    if(
        be.burnout_date is not null and d.stat_date >= be.burnout_date,
        true,
        false
    )                                                            as is_post_burnout,

    -- ── WASTED SPEND (spend after crossing burnout threshold) ─────────────────
    if(
        be.burnout_date is not null and d.stat_date >= be.burnout_date,
        d.spend_usd,
        0.0
    )                                                            as wasted_spend_usd,

    -- ── EFFICIENCY vs PEAK ───────────────────────────────────────────────────
    -- How efficient is this creative TODAY vs when it was at peak?
    round(
        d.ctr_7d_avg / nullif(p.absolute_peak_ctr, 0),
        4
    )                                                            as ctr_vs_peak_ratio,

    -- CPI premium: how much more expensive are installs now vs the creative's best day?
    round(
        d.cpi_usd / nullif(
            min(d.cpi_usd) over (partition by d.creative_id),
            0
        ),
        4
    )                                                            as cpi_vs_best_ratio

from daily d
inner join `marts_intermediate`.`int_creative_peaks` p
    on p.creative_id = d.creative_id
left join `marts_intermediate`.`int_burnout_events` be
    on be.creative_id = d.creative_id