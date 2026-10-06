select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select is_on_time
from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.fact_orders
where is_on_time is null



      
    ) dbt_internal_test