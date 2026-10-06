select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select ordered_qty
from ZERO_TO_ONE_CHAIN.PUBLIC_L2_STAGE.stg_purchase_orders
where ordered_qty is null



      
    ) dbt_internal_test