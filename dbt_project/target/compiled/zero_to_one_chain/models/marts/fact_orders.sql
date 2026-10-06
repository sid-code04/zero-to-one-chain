-- Conformed fact: sales orders enriched with customer + plant context and derived metrics


WITH orders AS (
    SELECT * FROM ZERO_TO_ONE_CHAIN.PUBLIC_L2_STAGE.stg_sales_orders
),

customers AS (
    SELECT
        customer_id,
        customer_name,
        customer_region,
        industry,
        segment,
        service_tier,
        sla_target_otd_pct,
        credit_risk,
        sla_contract
    FROM ZERO_TO_ONE_CHAIN.L1_INGESTION.RAW_ERP_CUSTOMERS
),

plants AS (
    SELECT
        plant_code AS plant_id,
        plant_name,
        region AS plant_region,
        country AS plant_country,
        plant_type
    FROM ZERO_TO_ONE_CHAIN.L1_INGESTION.RAW_ERP_PLANTS
),

enriched AS (
    SELECT
        o.order_number,
        o.order_header_id,
        o.line_item,
        o.order_date,
        DATE_TRUNC('MONTH', o.order_date) AS order_month,
        DATE_TRUNC('QUARTER', o.order_date) AS order_quarter,
        DAYOFWEEK(o.order_date) AS order_dow,
        o.order_type,
        o.order_status,

        -- Customer context
        o.customer_id,
        c.customer_name,
        c.customer_region,
        c.industry,
        c.segment,
        c.service_tier,
        c.credit_risk,

        -- Plant context
        o.plant_code,
        p.plant_name,
        p.plant_region,
        p.plant_country,

        -- Quantities
        o.ordered_qty,
        o.shipped_qty,
        o.delivered_qty,
        o.ordered_qty - o.delivered_qty AS shortfall_qty,
        o.uom,

        -- Financials
        o.unit_price_usd,
        o.line_value_usd,
        o.discount_pct,
        o.net_value_usd,
        o.freight_charge_usd,
        CASE WHEN o.ordered_qty > 0 THEN ROUND(o.net_value_usd / o.ordered_qty, 2) ELSE NULL END AS net_price_per_unit,

        -- Delivery dates + metrics
        o.requested_delivery_date,
        o.committed_delivery_date,
        o.actual_delivery_date,
        o.delivery_variance_days,
        o.is_on_time,
        o.is_in_full,
        o.is_otif,
        o.fill_rate_pct,

        -- SLA breach detection
        COALESCE(c.sla_target_otd_pct, 95) AS sla_target,
        CASE WHEN NOT o.is_on_time AND c.sla_contract = 'Yes' THEN TRUE ELSE FALSE END AS is_sla_breach,

        -- Aging: days since order
        DATEDIFF(DAY, o.order_date, COALESCE(o.actual_delivery_date, CURRENT_DATE())) AS order_age_days,
        CASE
            WHEN o.order_status IN ('CLOSED', 'INVOICED', 'DELIVERED') THEN 'COMPLETE'
            WHEN o.order_status = 'CANCELLED' THEN 'CANCELLED'
            WHEN DATEDIFF(DAY, o.committed_delivery_date, CURRENT_DATE()) > 14 THEN 'OVERDUE_CRITICAL'
            WHEN DATEDIFF(DAY, o.committed_delivery_date, CURRENT_DATE()) > 0 THEN 'OVERDUE'
            ELSE 'ON_TRACK'
        END AS order_health,

        -- Rolling window: rank within customer by value
        ROW_NUMBER() OVER (PARTITION BY o.customer_id ORDER BY o.net_value_usd DESC) AS customer_value_rank,

        o.ship_to_region,
        o.ship_to_country,
        o.shipping_method,
        o.shipment_ref,
        o.service_level,
        o.priority,
        o.channel
    FROM orders o
    LEFT JOIN customers c ON c.customer_id = o.customer_id
    LEFT JOIN plants p ON p.plant_id = o.plant_code
)

SELECT * FROM enriched