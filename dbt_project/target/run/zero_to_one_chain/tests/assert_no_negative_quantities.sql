select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      -- Test: no negative quantities should exist in staged purchase orders
SELECT po_number, ordered_qty
FROM ZERO_TO_ONE_CHAIN.PUBLIC_L2_STAGE.stg_purchase_orders
WHERE ordered_qty < 0
      
    ) dbt_internal_test