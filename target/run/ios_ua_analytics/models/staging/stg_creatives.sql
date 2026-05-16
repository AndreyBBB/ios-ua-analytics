

  create or replace view `marts_staging`.`stg_creatives` 
  
    
  
  
    
    
  as (
    -- stg_creatives: clean creative metadata, add format groupings

with source as (
    select * from `raw`.`creatives`
),

staged as (
    select
        creative_id,
        campaign_id,
        creative_name,
        format,
        size,
        toDate(launch_date)                                          as launch_date,

        -- Group formats for higher-level analysis
        case
            when format in ('video_15s', 'video_30s') then 'video'
            when format = 'static_image'              then 'static'
            when format = 'carousel'                  then 'carousel'
            else 'other'
        end                                                          as format_group,

        -- Is this a video creative? (often burns faster)
        if(format in ('video_15s', 'video_30s'), true, false)        as is_video,

        -- Video length in seconds (null for non-video)
        case
            when format = 'video_15s' then 15
            when format = 'video_30s' then 30
            else null
        end                                                          as video_length_seconds

    from source
    where creative_id is not null
)

select * from staged
    
  )
      
      
                    -- end_of_sql
                    
                    