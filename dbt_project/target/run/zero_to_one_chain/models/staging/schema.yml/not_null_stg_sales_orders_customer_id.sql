select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
    



select customer_id
from ZERO_TO_ONE_CHAIN.PUBLIC_L2_STAGE.stg_sales_orders
where customer_id is null



      
    ) dbt_internal_test