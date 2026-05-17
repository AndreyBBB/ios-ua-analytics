
  
    
    
    
        
         


        
  

  insert into `marts_intermediate`.`int_skan_cv_mapping__dbt_backup`
        ("install_date", "campaign_id", "creative_id", "network", "country", "skan_version", "postback_sequence", "postback_count", "fine_cv_count", "low_threshold_count", "medium_threshold_count", "cv_no_event", "cv_engagement", "cv_trial", "cv_low_revenue", "cv_mid_revenue", "cv_high_revenue", "revenue_signal_count", "estimated_revenue_usd", "avg_conversion_value", "monetisation_rate")-- int_skan_cv_mapping
-- ─────────────────────────────────────────────────────────────────────────────
-- Aggregates SKAN postbacks by (install_date, campaign_id, creative_id).
-- Decodes conversion value distribution → estimated revenue signals.
-- This is used in mart_skan_attribution and mart_unit_economics.
--
-- Key SKAN analytics concepts shown here:
--   - CV distribution: what fraction of users hit each revenue tier?
--   - Privacy threshold impact: how many postbacks are degraded to coarse?
--   - Postback sequence analysis: are users upgrading their CV over 3 windows?

with postbacks as (
    select * from `marts_staging`.`stg_skan_postbacks`
),

aggregated as (
    select
        install_date,
        campaign_id,
        creative_id,
        network,
        country,
        skan_version,
        postback_sequence,

        -- Volume
        count()                                             as postback_count,

        -- Privacy breakdown
        countIf(privacy_threshold = 'none')                 as fine_cv_count,
        countIf(privacy_threshold = 'low')                  as low_threshold_count,
        countIf(privacy_threshold = 'medium')               as medium_threshold_count,

        -- CV bucket distribution (for understanding monetisation funnel)
        countIf(cv_bucket = 'no_event')                     as cv_no_event,
        countIf(cv_bucket = 'engagement')                   as cv_engagement,
        countIf(cv_bucket = 'trial_start')                  as cv_trial,
        countIf(cv_bucket = 'low_revenue')                  as cv_low_revenue,
        countIf(cv_bucket = 'mid_revenue')                  as cv_mid_revenue,
        countIf(cv_bucket = 'high_revenue')                 as cv_high_revenue,

        -- Revenue signals
        countIf(has_revenue_signal = true)                  as revenue_signal_count,
        sum(estimated_revenue_usd)                          as estimated_revenue_usd,

        -- Average CV (useful for trend analysis)
        round(avg(conversion_value), 2)                     as avg_conversion_value,

        -- Monetisation rate: % of postbacks with revenue signal
        round(
            countIf(has_revenue_signal = true) / nullif(count(), 0),
            4
        )                                                   as monetisation_rate

    from postbacks
    group by
        install_date, campaign_id, creative_id,
        network, country, skan_version, postback_sequence
)

select * from aggregated
  