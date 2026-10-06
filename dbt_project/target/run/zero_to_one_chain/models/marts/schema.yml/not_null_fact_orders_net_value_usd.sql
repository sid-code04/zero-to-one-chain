select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select net_value_usd
from ZERO_TO_ONE_CHAIN_UAT.PUBLIC_L5_CORE.fact_orders
where net_value_usd is null



      
    ) dbt_internal_test