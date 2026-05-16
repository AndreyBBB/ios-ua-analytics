
    
    

select
    creative_id as unique_field,
    count(*) as n_records

from `raw`.`creatives`
where creative_id is not null
group by creative_id
having count(*) > 1


