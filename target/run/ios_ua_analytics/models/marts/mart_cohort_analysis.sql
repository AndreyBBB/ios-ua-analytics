
  
    
    
    
        
         


        
  

  insert into `marts_marts`.`mart_cohort_analysis__dbt_backup`
        ("install_date", "network", "country", "total_installs", "total_spend_usd", "cac_usd", "arpu_d0", "arpu_d1", "arpu_d3", "arpu_d7", "arpu_d14", "arpu_d30", "revenue_d7_usd", "revenue_d14_usd", "revenue_d30_usd", "roas_d7", "roas_d14", "roas_d30", "install_week")-- mart_cohort_analysis
-- ─────────────────────────────────────────────────────────────────────────────
-- Classic cohort retention + revenue table for BI.
-- One row per (install_date, network, country, cohort_day).
-- Powers the "Cohort Analysis" Power BI page: retention heatmap + LTV curves.
--
-- Cohort metrics at standard checkpoints: D1, D3, D7, D14, D30.

with cohort_installs as (
    select * from `marts_intermediate`.`int_cohort_installs`
),

cohort_revenue as (
    select * from `marts_intermediate`.`int_cohort_revenue`
),

-- Roll up installs to the install_date / network / country level
cohort_base as (
    select
        install_date,
        network,
        country,
        sum(cohort_installs)    as total_installs,
        sum(cohort_spend_usd)   as total_spend_usd,
        avg(cac_usd)            as avg_cac_usd
    from cohort_installs
    group by 1, 2, 3
),

-- Roll up revenue at the same level
revenue_agg as (
    select
        install_date,
        network,
        country,
        days_since_install,
        sum(daily_revenue_usd)  as revenue_usd,
        sum(cumulative_revenue_usd) as cum_revenue_usd,
        any(cohort_installs)    as installs,
        any(cohort_spend_usd)   as spend_usd
    from cohort_revenue
    group by 1, 2, 3, 4
),

-- Pivot to wide format (one row per cohort, columns for each checkpoint)
-- Using conditional aggregation for D1/D3/D7/D14/D30
cohort_wide as (
    select
        cb.install_date,
        cb.network,
        cb.country,
        cb.total_installs,
        cb.total_spend_usd,
        round(cb.avg_cac_usd, 4)                                     as cac_usd,

        -- Revenue at each checkpoint
        round(sumIf(ra.revenue_usd, ra.days_since_install = 0) / nullif(cb.total_installs, 0), 4)  as arpu_d0,
        round(sumIf(ra.revenue_usd, ra.days_since_install <= 1) / nullif(cb.total_installs, 0), 4)  as arpu_d1,
        round(sumIf(ra.revenue_usd, ra.days_since_install <= 3) / nullif(cb.total_installs, 0), 4)  as arpu_d3,
        round(sumIf(ra.revenue_usd, ra.days_since_install <= 7) / nullif(cb.total_installs, 0), 4)  as arpu_d7,
        round(sumIf(ra.revenue_usd, ra.days_since_install <= 14) / nullif(cb.total_installs, 0), 4) as arpu_d14,
        round(sumIf(ra.revenue_usd, ra.days_since_install <= 30) / nullif(cb.total_installs, 0), 4) as arpu_d30,

        -- Cumulative revenue totals
        round(sumIf(ra.revenue_usd, ra.days_since_install <= 7), 2)   as revenue_d7_usd,
        round(sumIf(ra.revenue_usd, ra.days_since_install <= 14), 2)  as revenue_d14_usd,
        round(sumIf(ra.revenue_usd, ra.days_since_install <= 30), 2)  as revenue_d30_usd,

        -- ROAS at each checkpoint
        round(
            sumIf(ra.revenue_usd, ra.days_since_install <= 7) / nullif(cb.total_spend_usd, 0),
            4
        )                                                              as roas_d7,
        round(
            sumIf(ra.revenue_usd, ra.days_since_install <= 14) / nullif(cb.total_spend_usd, 0),
            4
        )                                                              as roas_d14,
        round(
            sumIf(ra.revenue_usd, ra.days_since_install <= 30) / nullif(cb.total_spend_usd, 0),
            4
        )                                                              as roas_d30,

        -- Week-of-year (for aggregated trend charts)
        toMonday(cb.install_date)                                      as install_week

    from cohort_base cb
    left join revenue_agg ra
        on cb.install_date = ra.install_date
        and cb.network = ra.network
        and cb.country = ra.country
    group by 1, 2, 3, 4, 5, 6
)

select * from cohort_wide
order by install_date, network, country
  