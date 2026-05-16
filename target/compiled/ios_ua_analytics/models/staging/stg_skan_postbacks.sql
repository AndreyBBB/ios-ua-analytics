-- stg_skan_postbacks: clean SKAN postback data + decode conversion values

-- SKAN Conversion Value schema (6-bit, industry standard for subscription apps):
-- CV 0      = no meaningful event (install only)
-- CV 1-2    = engagement (tutorial, onboarding)
-- CV 3      = trial started
-- CV 4-7    = week 1 revenue tier
-- CV 8-15   = week 2+ revenue tier
-- CV 16-63  = higher revenue (used for SKAN 4 fine CV)

with source as (
    select * from `raw`.`skan_postbacks`
),

staged as (
    select
        postback_id,
        toDate(install_date)                                   as install_date,
        campaign_id,
        creative_id,
        network,
        country,
        skan_version,
        toUInt8(conversion_value)                              as conversion_value,
        toUInt8(postback_sequence)                             as postback_sequence,
        privacy_threshold,

        -- Decode CV into revenue bucket label (for BI readability)
        case
            when conversion_value = 0                     then 'no_event'
            when conversion_value between 1 and 2         then 'engagement'
            when conversion_value = 3                     then 'trial_start'
            when conversion_value between 4 and 7         then 'low_revenue'
            when conversion_value between 8 and 15        then 'mid_revenue'
            when conversion_value between 16 and 63       then 'high_revenue'
        end                                                    as cv_bucket,

        -- Estimated revenue from CV (approximate, used for SKAN-based LTV)
        case
            when conversion_value = 0                     then 0.0
            when conversion_value between 1 and 2         then 0.0
            when conversion_value = 3                     then 0.0     -- trial, no revenue yet
            when conversion_value between 4 and 5         then 9.99
            when conversion_value between 6 and 7         then 14.99
            when conversion_value between 8 and 11        then 29.99
            when conversion_value between 12 and 13       then 49.99
            when conversion_value between 14 and 15       then 79.99
            else (conversion_value - 15) * 3.0 + 99.99
        end                                                    as estimated_revenue_usd,

        -- Flag: does this postback have a meaningful revenue signal?
        if(conversion_value >= 4, true, false)                 as has_revenue_signal,

        -- Flag: postback quality (fine = full CV, coarse = limited info)
        if(privacy_threshold = 'none', 'fine', 'coarse')       as cv_quality

    from source
    where
        postback_id is not null
        and install_date is not null
        and conversion_value between 0 and 63
)

select * from staged