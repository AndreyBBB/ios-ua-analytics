
    
    

with all_values as (

    select
        network as value_field,
        count(*) as n_records

    from `raw`.`campaigns`
    group by network

)

select *
from all_values
where value_field not in (
    'Meta','Google_UAC','Apple_Search_Ads','TikTok','Snap'
)


