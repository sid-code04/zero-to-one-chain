-- Test: OTD % should be between 0 and 100 for all completed orders
SELECT order_number,
       CASE WHEN is_on_time THEN 1 ELSE 0 END AS otd_val
FROM ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.fact_orders
WHERE CASE WHEN is_on_time THEN 1 ELSE 0 END NOT BETWEEN 0 AND 1