
    
    

select
    postback_id as unique_field,
    count(*) as n_records

from `raw`.`skan_postbacks`
where postback_id is not null
group by postback_id
having count(*) > 1


