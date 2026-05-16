-- int_cohort_revenue
-- Revenue by (install_date, campaign_id, creative_id, days_since_install).
-- Powers LTV curve and payback period calculations.
--
-- ClickHouse note: CTEs containing window functions cannot be joined with other
-- CTEs or inline subqueries — ClickHouse raises scope or correlated-subquery
-- errors. Solution: no WITH clause at all; use nested subqueries instead.

select
    cr.install_date,
    cr.campaign_id,
    cr.creative_id,
    cr.network,
    cr.country,
    cr.days_since_install,
    cr.daily_revenue_usd,
    cr.cumulative_revenue_usd,
    ci.cohort_installs,
    ci.cohort_spend_usd,
    ci.cac_usd,
    round(cr.cumulative_revenue_usd / nullif(ci.cohort_installs, 0), 4)  as ltv_usd,
    round(cr.cumulative_revenue_usd / nullif(ci.cohort_spend_usd, 0), 4) as roas

from (
    -- Cumulative revenue via window function (no JOIN here)
    select
        install_date,
        campaign_id,
        creative_id,
        network,
        country,
        days_since_install,
        revenue_usd                                          as daily_revenue_usd,
        sum(revenue_usd) over (
            partition by install_date, campaign_id, creative_id
            order by days_since_install
            rows between unbounded preceding and current row
        )                                                    as cumulative_revenue_usd
    from (
        -- Daily revenue aggregation
        select
            install_date,
            campaign_id,
            creative_id,
            network,
            country,
            days_since_install,
            sum(revenue_usd) as revenue_usd
        from `marts_staging`.`stg_iap_events`
        where is_revenue_event = true
        group by
            install_date, campaign_id, creative_id,
            network, country, days_since_install
    )
) cr
left join `marts_intermediate`.`int_cohort_installs` ci
    on  ci.install_date = cr.install_date
    and ci.campaign_id  = cr.campaign_id
    and ci.creative_id  = cr.creative_id