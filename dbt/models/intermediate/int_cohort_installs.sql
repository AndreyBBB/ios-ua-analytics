-- int_cohort_installs
-- ─────────────────────────────────────────────────────────────────────────────
-- Cohort base table: one row per (install_date, campaign_id, creative_id).
-- Aggregates installs and spend by cohort date for LTV / ROAS calculations.
--
-- "Cohort" here = all users installed on the same day from the same source.
-- We don't have user IDs (privacy) — cohort-level is the correct approach for
-- SKAN-compliant analytics.
--
-- ClickHouse note: USING() in CTEs can cause the join column to be stored with
-- the source table's alias prefix (e.g. "s.campaign_id" instead of "campaign_id"),
-- breaking downstream JOINs. Fix: explicit ON conditions + explicit AS aliases
-- on every selected column so the materialized table has clean bare column names.

with ad_stats as (
    select * from {{ ref('stg_ad_stats') }}
),

campaigns as (
    select * from {{ ref('stg_campaigns') }}
),

creatives as (
    select * from {{ ref('stg_creatives') }}
),

-- Aggregate to cohort level
cohort_base as (
    select
        s.stat_date          as install_date,   -- cohort date = install date
        s.campaign_id        as campaign_id,
        s.creative_id        as creative_id,
        s.network            as network,
        s.country            as country,
        camp.objective       as objective,
        cre.format           as format,
        cre.format_group     as format_group,

        sum(s.installs)      as cohort_installs,
        sum(s.spend_usd)     as cohort_spend_usd,
        sum(s.clicks)        as cohort_clicks,
        sum(s.impressions)   as cohort_impressions,

        -- CAC: cost per acquired user for this cohort
        round(
            sum(s.spend_usd) / nullif(sum(s.installs), 0),
            4
        )                    as cac_usd,

        -- Click-to-install CVR for this cohort
        round(
            sum(s.installs) / nullif(sum(s.clicks), 0),
            6
        )                    as install_cvr

    from ad_stats s
    inner join campaigns camp on camp.campaign_id = s.campaign_id
    inner join creatives cre  on cre.creative_id  = s.creative_id
    where s.installs > 0
    group by
        install_date, campaign_id, creative_id,
        network, country, objective, format, format_group
)

select * from cohort_base
