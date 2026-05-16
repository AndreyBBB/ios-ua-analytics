
  
    
    
    
        
         


        
  

  insert into `marts_intermediate`.`int_burnout_events__dbt_backup`
        ("creative_id", "burnout_date", "burnout_day_of_life")-- int_burnout_events
-- ─────────────────────────────────────────────────────────────────────────────
-- One row per creative_id: the first date the creative crossed the burnout
-- threshold (7d-avg CTR fell below burnout_ctr_threshold × peak CTR),
-- AND the crossover happened after the peak day (decay phase only).
--
-- Materialized as a table to avoid ClickHouse multi-level CTE scope errors
-- when mart_creative_burnout JOINs this alongside int_creative_peaks.
-- ─────────────────────────────────────────────────────────────────────────────



select
    d.creative_id,
    min(d.stat_date)     as burnout_date,
    min(d.day_of_life)   as burnout_day_of_life

from `marts_intermediate`.`int_creative_daily_metrics` d
inner join `marts_intermediate`.`int_creative_peaks` p
    on p.creative_id = d.creative_id

where
    d.impressions >= 500
    and d.ctr_7d_avg < (p.absolute_peak_ctr * 0.7)
    and d.day_of_life > p.peak_day_of_life   -- must be past peak (decay phase only)

group by d.creative_id
  