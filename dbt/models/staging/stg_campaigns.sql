-- stg_campaigns: clean and type-cast raw campaign data
-- Adds derived fields: is_active, campaign_duration_days

with source as (
    select * from {{ source('raw', 'campaigns') }}
),

staged as (
    select
        campaign_id,
        campaign_name,
        network,
        objective,
        country,
        daily_budget                                             as daily_budget_usd,

        -- Normalise dates
        toDate(start_date)                                       as start_date,
        if(end_date is not null, toDate(end_date), null)         as end_date,

        -- Derived: is campaign currently active?
        if(
            end_date is null or toDate(end_date) >= today(),
            true,
            false
        )                                                        as is_active,

        -- Derived: planned/actual duration in days
        if(
            end_date is not null,
            dateDiff('day', toDate(start_date), toDate(end_date)),
            null
        )                                                        as campaign_duration_days

    from source
    where campaign_id is not null
)

select * from staged
