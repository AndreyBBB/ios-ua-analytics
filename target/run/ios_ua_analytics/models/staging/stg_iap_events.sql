

  create or replace view `marts_staging`.`stg_iap_events` 
  
    
  
  
    
    
  as (
    -- stg_iap_events: clean IAP events, categorise revenue types

with source as (
    select * from `raw`.`iap_events`
),

staged as (
    select
        event_id,
        toDate(install_date)                                      as install_date,
        toDate(event_date)                                        as event_date,
        campaign_id,
        creative_id,
        network,
        country,
        event_type,
        product_id,
        toFloat64(revenue_usd)                                    as revenue_usd,

        -- Days from install to this event (cohort day)
        dateDiff('day', toDate(install_date), toDate(event_date)) as days_since_install,

        -- Product tier for grouping
        case
            when product_id = 'weekly_sub'  then 'weekly'
            when product_id = 'monthly_sub' then 'monthly'
            when product_id = 'annual_sub'  then 'annual'
            when product_id = 'lifetime'    then 'lifetime'
            else 'other'
        end                                                       as product_tier,

        -- Is this a monetising event? (not trial)
        if(event_type != 'trial_start', true, false)              as is_revenue_event,

        -- Normalise: monthly revenue equivalent for LTV comparison
        case
            when product_id = 'weekly_sub'  then revenue_usd * 4.33
            when product_id = 'monthly_sub' then revenue_usd
            when product_id = 'annual_sub'  then revenue_usd / 12.0
            when product_id = 'lifetime'    then revenue_usd / 24.0  -- amortised over 2 years
            else revenue_usd
        end                                                       as monthly_equivalent_usd

    from source
    where
        event_id is not null
        and install_date is not null
        and event_date >= install_date       -- sanity: event can't precede install
        and revenue_usd >= 0
)

select * from staged
    
  )
      
      
                    -- end_of_sql
                    
                    