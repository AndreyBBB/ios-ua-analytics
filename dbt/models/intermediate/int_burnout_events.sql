-- int_burnout_events
-- ─────────────────────────────────────────────────────────────────────────────
-- One row per creative_id: the first date the creative crossed the burnout
-- threshold (7d-avg CTR fell below burnout_ctr_threshold × peak CTR),
-- AND the crossover happened after the peak day (decay phase only).
--
-- Materialized as a table to avoid ClickHouse multi-level CTE scope errors
-- when mart_creative_burnout JOINs this alongside int_creative_peaks.
-- ─────────────────────────────────────────────────────────────────────────────

{{ config(materialized = 'table') }}

select
    d.creative_id,
    min(d.stat_date)     as burnout_date,
    min(d.day_of_life)   as burnout_day_of_life

from {{ ref('int_creative_daily_metrics') }} d
inner join {{ ref('int_creative_peaks') }} p
    on p.creative_id = d.creative_id

where
    d.impressions >= {{ var('min_impressions_for_burnout') }}
    and d.ctr_7d_avg < (p.absolute_peak_ctr * {{ var('burnout_ctr_threshold') }})
    and d.day_of_life > p.peak_day_of_life   -- must be past peak (decay phase only)

group by d.creative_id
