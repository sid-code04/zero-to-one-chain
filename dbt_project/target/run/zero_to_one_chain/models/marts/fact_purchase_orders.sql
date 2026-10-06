
  
    

        create or replace transient table ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.fact_purchase_orders
         as
        (-- Conformed fact: purchase orders enriched with supplier risk + cost analytics


WITH pos AS (
    SELECT * FROM ZERO_TO_ONE_CHAIN.PUBLIC_L2_STAGE.stg_purchase_orders
),

suppliers AS (
    SELECT
        supplier_id,
        supplier_name AS supplier_name,
        region AS supplier_region,
        country AS supplier_country,
        tier,
        blended_risk_score,
        health_tier,
        dual_source_available
    FROM ZERO_TO_ONE_CHAIN.PUBLIC_L5_CORE.dim_supplier
),

materials AS (
    SELECT
        material_number,
        material_description,
        material_type,
        material_group,
        category,
        family,
        abc_class,
        standard_cost_usd
    FROM ZERO_TO_ONE_CHAIN.L1_INGESTION.RAW_ERP_MATERIALS
),

enriched AS (
    SELECT
        po.po_number,
        po.po_header_id,
        po.line_number,
        po.po_date,
        DATE_TRUNC('MONTH', po.po_date) AS po_month,
        DATE_TRUNC('QUARTER', po.po_date) AS po_quarter,
        po.po_type,
        po.po_status,

        -- Supplier context
        po.supplier_id,
        s.supplier_name,
        s.supplier_region,
        s.supplier_country,
        s.tier AS supplier_tier,
        s.blended_risk_score AS supplier_risk_score,
        s.health_tier AS supplier_health,
        s.dual_source_available,

        -- Material context
        po.material_number,
        m.material_description,
        m.material_type,
        po.material_group,
        m.category,
        m.family,
        m.abc_class,

        -- Quantities
        po.ordered_qty,
        po.received_qty,
        po.rejected_qty,
        po.ordered_qty - po.received_qty AS open_qty,
        CASE WHEN po.ordered_qty > 0
             THEN ROUND(po.rejected_qty / po.ordered_qty * 100, 2)
             ELSE 0
        END AS reject_rate_pct,
        po.uom,

        -- Financials
        po.unit_price_usd,
        po.extended_price_usd,
        po.discount_pct,
        po.freight_cost_usd,
        po.duty_cost_usd,
        po.handling_cost_usd,
        po.landed_cost_usd,
        CASE WHEN po.ordered_qty > 0
             THEN ROUND(po.landed_cost_usd / po.ordered_qty, 2)
             ELSE NULL
        END AS landed_cost_per_unit,

        -- Cost variance: actual vs standard
        CASE WHEN m.standard_cost_usd > 0 AND po.ordered_qty > 0
             THEN ROUND((po.landed_cost_usd / po.ordered_qty - m.standard_cost_usd) / m.standard_cost_usd * 100, 2)
             ELSE NULL
        END AS cost_variance_pct,

        -- Delivery
        po.requested_delivery_date,
        po.confirmed_delivery_date,
        po.actual_delivery_date,
        po.delivery_variance_days,
        po.is_on_time,
        po.is_in_full,
        po.is_otif,

        -- Lead time
        DATEDIFF(DAY, po.po_date, po.confirmed_delivery_date) AS planned_lead_time_days,
        DATEDIFF(DAY, po.po_date, po.actual_delivery_date) AS actual_lead_time_days,

        -- Risk flags
        CASE
            WHEN s.health_tier = 'RED' THEN 'HIGH_RISK_SUPPLIER'
            WHEN po.rejected_qty > 0 THEN 'QUALITY_ISSUE'
            WHEN NOT po.is_on_time AND po.actual_delivery_date IS NOT NULL THEN 'LATE_DELIVERY'
            WHEN s.dual_source_available = 'No' AND m.abc_class = 'A' THEN 'SINGLE_SOURCE_CRITICAL'
            ELSE 'NORMAL'
        END AS risk_flag,

        po.priority,
        po.order_source,
        po.cost_center,
        po.project_code,
        po.plant_code
    FROM pos po
    LEFT JOIN suppliers s ON s.supplier_id = po.supplier_id
    LEFT JOIN materials m ON m.material_number = po.material_number
)

SELECT * FROM enriched
        );
      
  