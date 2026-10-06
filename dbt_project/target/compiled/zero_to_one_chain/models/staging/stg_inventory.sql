-- Staged inventory snapshots


SELECT
    snapshot_date::DATE AS snapshot_date,
    UPPER(TRIM(plant_code)) AS plant_code,
    UPPER(TRIM(material_number)) AS material_number,
    UPPER(TRIM(storage_location)) AS storage_location,
    GREATEST(on_hand_qty, 0) AS on_hand_qty,
    GREATEST(allocated_qty, 0) AS allocated_qty,
    GREATEST(on_hand_qty - allocated_qty, 0) AS available_qty,
    GREATEST(in_transit_qty, 0) AS in_transit_qty,
    GREATEST(on_order_qty, 0) AS on_order_qty,
    GREATEST(quarantine_qty, 0) AS quarantine_qty,
    unit_cost_usd,
    ROUND(GREATEST(on_hand_qty, 0) * unit_cost_usd, 2) AS inventory_value_usd,
    reorder_point,
    safety_stock_qty,
    CASE
        WHEN on_hand_qty <= 0 THEN 'STOCKOUT'
        WHEN on_hand_qty <= reorder_point THEN 'BELOW_ROP'
        WHEN on_hand_qty <= safety_stock_qty THEN 'BELOW_SAFETY'
        ELSE 'ADEQUATE'
    END AS stock_status,
    days_on_hand,
    UPPER(TRIM(abc_classification)) AS abc_class,
    turnover_ratio,
    obsolescence_risk_pct,
    carrying_cost_usd_daily,
    _loaded_at,
    _source_system
FROM ZERO_TO_ONE_CHAIN.L1_INGESTION.RAW_ERP_INVENTORY_SNAPSHOTS