
  
    
    
    
        
         


        
  

  insert into `marts_intermediate`.`int_creative_peaks__dbt_backup`
        ("creative_id", "absolute_peak_ctr", "first_stat_date", "peak_day_of_life")-- int_creative_peaks
-- ─────────────────────────────────────────────────────────────────────────────
-- One row per creative_id: the absolute peak CTR, first active date,
-- and day_of_life at which the peak occurred.
--
-- Materialized as a table so mart_creative_burnout and int_burnout_events can
-- JOIN it without triggering ClickHouse's multi-level CTE scope errors.
-- ─────────────────────────────────────────────────────────────────────────────



select
    creative_id,
    max(ctr)                  as absolute_peak_ctr,
    min(stat_date)            as first_stat_date,
    argMax(day_of_life, ctr)  as peak_day_of_life

from `marts_intermediate`.`int_creative_daily_metrics`
where impressions >= 500
group by creative_id
  