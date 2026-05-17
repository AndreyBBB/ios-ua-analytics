-- int_creative_peaks
-- ─────────────────────────────────────────────────────────────────────────────
-- One row per creative_id: the absolute peak CTR, first active date,
-- and day_of_life at which the peak occurred.
--
-- Materialized as a table so mart_creative_burnout and int_burnout_events can
-- JOIN it without triggering ClickHouse's multi-level CTE scope errors.
-- ─────────────────────────────────────────────────────────────────────────────

{{ config(materialized = 'table') }}

select
    creative_id,
    max(ctr)                  as absolute_peak_ctr,
    min(stat_date)            as first_stat_date,
    argMax(day_of_life, ctr)  as peak_day_of_life

from {{ ref('int_creative_daily_metrics') }}
where impressions >= {{ var('min_impressions_for_burnout') }}
group by creative_id
