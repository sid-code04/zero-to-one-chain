select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select health_tier
from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.dim_supplier
where health_tier is null



      
    ) dbt_internal_test