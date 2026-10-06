
  create or replace   view ZERO_TO_ONE_CHAIN.PUBLIC_L2_STAGE.stg_purchase_orders
  
   as (
    -- Staged purchase orders: typed, normalized, standardized OTD logic


SELECT
    po_number,
    po_header_id,
    line_number,
    po_date::DATE AS po_date,
    UPPER(TRIM(po_type)) AS po_type,
    UPPER(TRIM(po_status)) AS po_status,
    UPPER(TRIM(vendor_code)) AS supplier_id,
    UPPER(TRIM(receiving_plant)) AS plant_code,
    UPPER(TRIM(material_number)) AS material_number,
    UPPER(TRIM(material_group)) AS material_group,
    GREATEST(ordered_qty, 0) AS ordered_qty,
    GREATEST(received_qty, 0) AS received_qty,
    GREATEST(rejected_qty, 0) AS rejected_qty,
    UPPER(TRIM(uom)) AS uom,
    unit_price AS unit_price_local,
    UPPER(TRIM(price_currency)) AS price_currency,
    fx_rate_to_usd,
    ROUND(unit_price / NULLIF(fx_rate_to_usd, 0), 4) AS unit_price_usd,
    ROUND(ordered_qty * unit_price / NULLIF(fx_rate_to_usd, 0), 2) AS extended_price_usd,
    discount_pct,
    freight_cost_usd,
    duty_cost_usd,
    handling_cost_usd,
    ROUND(
        ordered_qty * unit_price / NULLIF(fx_rate_to_usd, 0)
        + COALESCE(freight_cost_usd, 0)
        + COALESCE(duty_cost_usd, 0)
        + COALESCE(handling_cost_usd, 0), 2
    ) AS landed_cost_usd,
    requested_delivery_date::DATE AS requested_delivery_date,
    confirmed_delivery_date::DATE AS confirmed_delivery_date,
    actual_delivery_date::DATE AS actual_delivery_date,
    DATEDIFF(DAY, confirmed_delivery_date, actual_delivery_date) AS delivery_variance_days,
    CASE WHEN actual_delivery_date IS NOT NULL AND actual_delivery_date <= confirmed_delivery_date THEN TRUE ELSE FALSE END AS is_on_time,
    CASE WHEN actual_delivery_date IS NOT NULL AND received_qty >= ordered_qty THEN TRUE ELSE FALSE END AS is_in_full,
    CASE WHEN actual_delivery_date IS NOT NULL AND actual_delivery_date <= confirmed_delivery_date AND received_qty >= ordered_qty THEN TRUE ELSE FALSE END AS is_otif,
    UPPER(TRIM(priority)) AS priority,
    UPPER(TRIM(order_source)) AS order_source,
    cost_center,
    project_code,
    _loaded_at,
    _source_system
FROM ZERO_TO_ONE_CHAIN.L1_INGESTION.RAW_ERP_PURCHASE_ORDERS
  );

