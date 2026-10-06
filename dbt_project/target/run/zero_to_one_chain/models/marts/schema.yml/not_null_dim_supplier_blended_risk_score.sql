select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select blended_risk_score
from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.dim_supplier
where blended_risk_score is null



      
    ) dbt_internal_test