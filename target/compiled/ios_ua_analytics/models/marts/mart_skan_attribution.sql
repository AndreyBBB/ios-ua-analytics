-- mart_skan_attribution
-- ─────────────────────────────────────────────────────────────────────────────
-- SKAN 4.0 attribution summary for BI — one row per (install_date, campaign_id).
-- Shows the quality and completeness of the SKAN signal and estimates
-- revenue from conversion values where MMP tracking is unavailable.
--
-- This table demonstrates SKAN expertise in the portfolio:
--   - Privacy threshold impact analysis
--   - CV distribution & funnel (install → engagement → trial → revenue)
--   - SKAN vs non-SKAN install reconciliation
--
-- ClickHouse notes:
--   • USING replaced with ON (USING stores column with table alias prefix)
--   • camp.campaign_name / camp.objective have explicit AS aliases
--   • Named GROUP BY throughout (no positional)
--   • r.* from reconciled CTE is safe: reconciled only has coalesce() columns

with skan as (
    select * from `marts_intermediate`.`int_skan_cv_mapping`
    where postback_sequence = 1          -- primary postback (install window)
),

ad_stats as (
    select
        stat_date                         as install_date,
        campaign_id                       as campaign_id,
        creative_id                       as creative_id,
        network                           as network,
        country                           as country,
        sum(installs)                     as reported_installs,
        sum(spend_usd)                    as spend_usd
    from `marts_staging`.`stg_ad_stats`
    group by stat_date, campaign_id, creative_id, network, country
),

campaigns as (
    select * from `marts_staging`.`stg_campaigns`
),

-- Join SKAN postbacks with ad stats for reconciliation
reconciled as (
    select
        coalesce(s.install_date, a.install_date)    as install_date,
        coalesce(s.campaign_id, a.campaign_id)      as campaign_id,
        coalesce(s.creative_id, a.creative_id)      as creative_id,
        coalesce(s.network, a.network)              as network,
        coalesce(s.country, a.country)              as country,

        -- SKAN postback volumes
        coalesce(s.postback_count, 0)               as skan_postbacks,
        coalesce(s.fine_cv_count, 0)                as fine_cv_postbacks,
        coalesce(s.low_threshold_count, 0)          as low_threshold_postbacks,
        coalesce(s.medium_threshold_count, 0)       as medium_threshold_postbacks,

        -- CV funnel
        coalesce(s.cv_no_event, 0)                  as cv_no_event,
        coalesce(s.cv_engagement, 0)                as cv_engagement,
        coalesce(s.cv_trial, 0)                     as cv_trial,
        coalesce(s.cv_low_revenue, 0)               as cv_low_revenue,
        coalesce(s.cv_mid_revenue, 0)               as cv_mid_revenue,
        coalesce(s.cv_high_revenue, 0)              as cv_high_revenue,

        -- Revenue signal
        coalesce(s.revenue_signal_count, 0)         as revenue_signal_postbacks,
        coalesce(s.estimated_revenue_usd, 0)        as skan_estimated_revenue_usd,
        coalesce(s.monetisation_rate, 0)            as skan_monetisation_rate,
        coalesce(s.avg_conversion_value, 0)         as avg_cv,

        -- MMP-reported installs (for reconciliation)
        coalesce(a.reported_installs, 0)            as mmp_installs,
        coalesce(a.spend_usd, 0)                    as spend_usd

    from skan s
    full outer join ad_stats a
        on  s.install_date = a.install_date
        and s.campaign_id  = a.campaign_id
        and s.creative_id  = a.creative_id
        and s.network      = a.network
        and s.country      = a.country
),

-- Add derived analytics columns
final as (
    select
        r.install_date                  as install_date,
        r.campaign_id                   as campaign_id,
        r.creative_id                   as creative_id,
        r.network                       as network,
        r.country                       as country,
        r.skan_postbacks                as skan_postbacks,
        r.fine_cv_postbacks             as fine_cv_postbacks,
        r.low_threshold_postbacks       as low_threshold_postbacks,
        r.medium_threshold_postbacks    as medium_threshold_postbacks,
        r.cv_no_event                   as cv_no_event,
        r.cv_engagement                 as cv_engagement,
        r.cv_trial                      as cv_trial,
        r.cv_low_revenue                as cv_low_revenue,
        r.cv_mid_revenue                as cv_mid_revenue,
        r.cv_high_revenue               as cv_high_revenue,
        r.revenue_signal_postbacks      as revenue_signal_postbacks,
        r.skan_estimated_revenue_usd    as skan_estimated_revenue_usd,
        r.skan_monetisation_rate        as skan_monetisation_rate,
        r.avg_cv                        as avg_cv,
        r.mmp_installs                  as mmp_installs,
        r.spend_usd                     as spend_usd,
        camp.campaign_name              as campaign_name,
        camp.objective                  as objective,

        -- SKAN coverage: what % of MMP installs got a SKAN postback?
        round(
            r.skan_postbacks / nullif(r.mmp_installs, 0),
            4
        )                                                    as skan_coverage_rate,

        -- Privacy loss rate: % of postbacks that are degraded (medium threshold)
        round(
            r.medium_threshold_postbacks / nullif(r.skan_postbacks, 0),
            4
        )                                                    as privacy_loss_rate,

        -- Fine signal rate: % with full conversion value
        round(
            r.fine_cv_postbacks / nullif(r.skan_postbacks, 0),
            4
        )                                                    as fine_signal_rate,

        -- Trial-to-revenue ratio from SKAN (funnel health)
        round(
            (r.cv_low_revenue + r.cv_mid_revenue + r.cv_high_revenue)
            / nullif(r.cv_trial + r.cv_low_revenue + r.cv_mid_revenue + r.cv_high_revenue, 0),
            4
        )                                                    as trial_to_revenue_rate,

        -- SKAN-estimated CPI
        round(r.spend_usd / nullif(r.skan_postbacks, 0), 4) as skan_cpi_usd,

        -- SKAN-estimated ROAS (using CV-decoded revenue)
        round(
            r.skan_estimated_revenue_usd / nullif(r.spend_usd, 0),
            4
        )                                                    as skan_roas

    from reconciled r
    left join campaigns camp
        on camp.campaign_id = r.campaign_id
)

select * from final
order by install_date desc, spend_usd desc