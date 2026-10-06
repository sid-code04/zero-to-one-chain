select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select plant_code
from ZERO_TO_ONE_CHAIN.PUBLIC_L2_STAGE.stg_inventory
where plant_code is null



      
    ) dbt_internal_test