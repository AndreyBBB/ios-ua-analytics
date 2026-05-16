-- mart_campaign_performance
-- ─────────────────────────────────────────────────────────────────────────────
-- Daily campaign performance summary for BI overview page.
-- One row per (stat_date, campaign_id, network, country).
-- Includes saturation signal and traffic mix shift detection.

with ad_stats as (
    select * from `marts_staging`.`stg_ad_stats`
),

campaigns as (
    select * from `marts_staging`.`stg_campaigns`
),

daily_campaign as (
    select
        s.stat_date,
        s.campaign_id,
        s.network,
        s.country,
        camp.campaign_name,
        camp.objective,
        camp.daily_budget_usd,

        -- Daily totals
        sum(s.impressions)                                       as impressions,
        sum(s.clicks)                                            as clicks,
        sum(s.spend_usd)                                         as spend_usd,
        sum(s.installs)                                          as installs,

        -- Count of active creatives this day
        count(distinct s.creative_id)                            as active_creatives,

        -- Blended metrics (spend-weighted average across creatives)
        round(sum(s.clicks) / nullif(sum(s.impressions), 0), 6) as blended_ctr,
        round(sum(s.spend_usd) / nullif(sum(s.installs), 0), 4) as blended_cpi_usd,
        round((sum(s.spend_usd) / nullif(sum(s.impressions), 0)) * 1000, 4) as blended_cpm_usd,

        -- Budget utilisation: actual spend vs daily budget
        round(
            sum(s.spend_usd) / nullif(camp.daily_budget_usd, 0),
            4
        )                                                        as budget_utilisation_rate

    from ad_stats s
    inner join campaigns camp using (campaign_id)
    group by 1, 2, 3, 4, 5, 6, 7
),

-- Add rolling 7-day and 14-day trend context (for saturation detection)
with_trends as (
    select
        *,

        -- 7-day rolling average CPI (trend line)
        round(avg(blended_cpi_usd) over (
            partition by campaign_id
            order by stat_date
            rows between 6 preceding and current row
        ), 4)                                                    as cpi_7d_avg,

        -- 14-day rolling average CTR
        round(avg(blended_ctr) over (
            partition by campaign_id
            order by stat_date
            rows between 13 preceding and current row
        ), 6)                                                    as ctr_14d_avg,

        -- Cumulative spend (for pacing / budget burn charts)
        round(sum(spend_usd) over (
            partition by campaign_id
            order by stat_date
            rows between unbounded preceding and current row
        ), 2)                                                    as cumulative_spend_usd,

        -- Cumulative installs
        sum(installs) over (
            partition by campaign_id
            order by stat_date
            rows between unbounded preceding and current row
        )                                                        as cumulative_installs,

        -- CPI trend vs 14-day avg: are installs getting more expensive?
        round(
            blended_cpi_usd / nullif(
                avg(blended_cpi_usd) over (
                    partition by campaign_id
                    order by stat_date
                    rows between 13 preceding and 1 preceding
                ),
                0
            ),
            4
        )                                                        as cpi_trend_ratio

    from daily_campaign
),

-- Saturation flag: CPI > 130% of 14d average = potential saturation signal
with_flags as (
    select
        *,

        -- Saturation: CPI spiking above historical baseline
        case
            when cpi_trend_ratio > 1.30 then 'saturating'
            when cpi_trend_ratio > 1.15 then 'watch'
            when cpi_trend_ratio < 0.90 then 'improving'
            else 'stable'
        end                                                      as saturation_flag,

        -- Over-budget flag
        if(budget_utilisation_rate > 1.05, true, false)          as is_over_budget,

        -- Week number for aggregated charts
        toMonday(stat_date)                                      as stat_week

    from with_trends
)

select * from with_flags
order by stat_date desc, spend_usd desc