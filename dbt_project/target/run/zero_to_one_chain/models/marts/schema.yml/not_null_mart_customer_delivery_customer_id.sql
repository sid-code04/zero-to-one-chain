select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select customer_id
from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.mart_customer_delivery
where customer_id is null



      
    ) dbt_internal_test