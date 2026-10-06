select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select supplier_id
from ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.mart_supplier_scorecard
where supplier_id is null



      
    ) dbt_internal_test