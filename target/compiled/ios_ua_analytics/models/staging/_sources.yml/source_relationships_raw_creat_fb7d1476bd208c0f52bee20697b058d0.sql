
    
    

with child as (
    select campaign_id as from_field
    from `raw`.`creatives`
    where campaign_id is not null
),

parent as (
    select campaign_id as to_field
    from `raw`.`campaigns`
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null
-- end_of_sql
settings join_use_nulls = 1


