-- Test: no negative quantities should exist in staged purchase orders
SELECT po_number, ordered_qty
FROM {{ ref('stg_purchase_orders') }}
WHERE ordered_qty < 0
