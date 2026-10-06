-- Test: every supplier in fact_purchase_orders should exist in dim_supplier
SELECT DISTINCT fpo.supplier_id
FROM {{ ref('fact_purchase_orders') }} fpo
LEFT JOIN {{ ref('dim_supplier') }} ds ON ds.supplier_id = fpo.supplier_id
WHERE ds.supplier_id IS NULL AND fpo.supplier_id IS NOT NULL
