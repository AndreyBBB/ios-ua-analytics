
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

select
    postback_id as unique_field,
    count(*) as n_records

from `raw`.`skan_postbacks`
where postback_id is not null
group by postback_id
having count(*) > 1



  
  
    ) dbt_internal_test