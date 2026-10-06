-- Test: every supplier in fact_purchase_orders should exist in dim_supplier
SELECT DISTINCT fpo.supplier_id
FROM ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.fact_purchase_orders fpo
LEFT JOIN ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.dim_supplier ds ON ds.supplier_id = fpo.supplier_id
WHERE ds.supplier_id IS NULL AND fpo.supplier_id IS NOT NULL