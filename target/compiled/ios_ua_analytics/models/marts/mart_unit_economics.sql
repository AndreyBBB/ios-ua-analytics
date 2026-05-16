-- mart_unit_economics
-- ─────────────────────────────────────────────────────────────────────────────
-- Campaign-level unit economics summary for BI.
-- One row per (campaign_id, cohort snapshot: 7d / 14d / 30d).
--
-- Answers:
--   • What is the CAC for each campaign?
--   • What is the LTV at D7, D14, D30?
--   • What is ROAS at each checkpoint?
--   • When does each campaign pay back (payback_days)?
--
-- This is the primary table for the "Unit Economics" Power BI page.

with cohort_installs as (
    select * from `marts_intermediate`.`int_cohort_installs`
),

cohort_revenue as (
    select * from `marts_intermediate`.`int_cohort_revenue`
),

campaigns as (
    select * from `marts_staging`.`stg_campaigns`
),

-- Aggregate cohorts to campaign level
campaign_cohorts as (
    select
        ci.campaign_id          as campaign_id,
        ci.network              as network,
        ci.country              as country,
        camp.campaign_name      as campaign_name,
        camp.objective          as objective,
        camp.daily_budget_usd   as daily_budget_usd,

        -- Cohort totals
        sum(ci.cohort_installs)                              as total_installs,
        sum(ci.cohort_spend_usd)                             as total_spend_usd,

        -- Campaign-level CAC
        round(
            sum(ci.cohort_spend_usd) / nullif(sum(ci.cohort_installs), 0),
            4
        )                                                    as cac_usd

    from cohort_installs ci
    inner join campaigns camp ON camp.campaign_id = ci.campaign_id
    group by campaign_id, network, country, campaign_name, objective, daily_budget_usd
),

-- LTV at key cohort checkpoints
ltv_checkpoints as (
    select
        campaign_id,
        network,
        country,

        -- LTV at D7: cumulative revenue per install by day 7
        sumIf(daily_revenue_usd, days_since_install <= 7)
            / nullif(any(cohort_installs), 0)               as ltv_d7_usd,

        -- LTV at D14
        sumIf(daily_revenue_usd, days_since_install <= 14)
            / nullif(any(cohort_installs), 0)               as ltv_d14_usd,

        -- LTV at D30
        sumIf(daily_revenue_usd, days_since_install <= 30)
            / nullif(any(cohort_installs), 0)               as ltv_d30_usd,

        -- Total observed LTV (all days in simulation)
        sum(daily_revenue_usd)
            / nullif(any(cohort_installs), 0)               as ltv_total_usd,

        -- Total observed revenue
        sum(daily_revenue_usd)                               as total_revenue_usd

    from cohort_revenue
    group by campaign_id, network, country
),

-- ROAS at key checkpoints (revenue / spend)
combined as (
    select
        cc.campaign_id,
        cc.campaign_name,
        cc.network,
        cc.country,
        cc.objective,
        cc.daily_budget_usd,
        cc.total_installs,
        cc.total_spend_usd,
        cc.cac_usd,

        -- LTV checkpoints
        round(lv.ltv_d7_usd, 4)                              as ltv_d7_usd,
        round(lv.ltv_d14_usd, 4)                             as ltv_d14_usd,
        round(lv.ltv_d30_usd, 4)                             as ltv_d30_usd,
        round(lv.ltv_total_usd, 4)                           as ltv_total_usd,
        lv.total_revenue_usd,

        -- ROAS at each checkpoint (revenue / spend ratio)
        round(lv.ltv_d7_usd  / nullif(cc.cac_usd, 0), 4)    as roas_d7,
        round(lv.ltv_d14_usd / nullif(cc.cac_usd, 0), 4)    as roas_d14,
        round(lv.ltv_d30_usd / nullif(cc.cac_usd, 0), 4)    as roas_d30,
        round(lv.ltv_total_usd / nullif(cc.cac_usd, 0), 4)  as roas_total,

        -- Overall campaign ROAS (total revenue / total spend)
        round(
            lv.total_revenue_usd / nullif(cc.total_spend_usd, 0),
            4
        )                                                    as campaign_roas,

        -- Payback flag at each window
        if(lv.ltv_d7_usd  >= cc.cac_usd, 'paid_back', 'not_yet') as payback_d7,
        if(lv.ltv_d14_usd >= cc.cac_usd, 'paid_back', 'not_yet') as payback_d14,
        if(lv.ltv_d30_usd >= cc.cac_usd, 'paid_back', 'not_yet') as payback_d30,

        -- Estimated payback period (days) — which checkpoint does LTV cross CAC?
        case
            when lv.ltv_d7_usd  >= cc.cac_usd then '≤ 7 days'
            when lv.ltv_d14_usd >= cc.cac_usd then '8–14 days'
            when lv.ltv_d30_usd >= cc.cac_usd then '15–30 days'
            else '> 30 days'
        end                                                  as payback_period_bucket

    from campaign_cohorts cc
    left join ltv_checkpoints lv
        ON  lv.campaign_id = cc.campaign_id
        AND lv.network     = cc.network
        AND lv.country     = cc.country
)

select * from combined
order by campaign_roas desc