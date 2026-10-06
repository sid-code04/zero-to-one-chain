select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select landed_cost_usd
from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.fact_purchase_orders
where landed_cost_usd is null



      
    ) dbt_internal_test