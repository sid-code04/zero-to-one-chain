-- L6 Semantic: metric views and the consistency proof
-- Reference DDL extracted from the deployed DEV database ZERO_TO_ONE_CHAIN (GET_DDL), so it matches what is running.
-- Other environments are built from DEV by SP_DEPLOY_ENVIRONMENT (see 90_release.sql).
USE DATABASE ZERO_TO_ONE_CHAIN;

create or replace TABLE ZERO_TO_ONE_CHAIN.L6_SEMANTIC.CONSISTENCY_PROOF (
	PROOF_ID NUMBER(38,0) autoincrement start 1 increment 1 noorder,
	RUN_AT TIMESTAMP_LTZ(9) DEFAULT CURRENT_TIMESTAMP(),
	QUESTION VARCHAR(16777216) NOT NULL,
	METRIC_NAME VARCHAR(16777216) NOT NULL,
	PLANNER_RESULT NUMBER(15,4),
	PROCUREMENT_RESULT NUMBER(15,4),
	LOGISTICS_RESULT NUMBER(15,4),
	ALL_MATCH BOOLEAN,
	NOTES VARCHAR(16777216)
);

create or replace view ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_INVENTORY(
	SNAPSHOT_DATE,
	SNAPSHOT_MONTH,
	PLANT_CODE,
	PLANT_NAME,
	REGION,
	MATERIAL_NUMBER,
	PART_NAME,
	CATEGORY,
	FAMILY,
	ABC_CLASS,
	ON_HAND_QTY,
	AVAILABLE_QTY,
	IN_TRANSIT_QTY,
	ON_ORDER_QTY,
	QUARANTINE_QTY,
	INVENTORY_VALUE_USD,
	STOCK_STATUS,
	DAYS_ON_HAND,
	DAYS_OF_INVENTORY,
	TURNOVER_RATIO,
	OBSOLESCENCE_RISK_PCT,
	REORDER_POINT,
	SAFETY_STOCK_QTY,
	CARRYING_COST_USD_DAILY
) COMMENT='Canonical inventory metrics. DOI = on-hand qty / average daily demand. Stock status vs safety stock and reorder point.'
 as
SELECT
    i.snapshot_date, DATE_TRUNC('MONTH', i.snapshot_date) AS snapshot_month,
    i.plant_code, p.plant_name, p.region,
    i.material_number, pt.part_name, pt.category, pt.family, i.abc_class,
    i.on_hand_qty, i.available_qty, i.in_transit_qty, i.on_order_qty, i.quarantine_qty,
    i.inventory_value_usd,
    CASE WHEN i.on_hand_qty <= 0 THEN 'STOCKOUT'
         WHEN i.on_hand_qty < i.safety_stock_qty THEN 'BELOW_SAFETY'
         WHEN i.on_hand_qty < i.reorder_point THEN 'BELOW_ROP'
         ELSE 'ADEQUATE' END AS stock_status,
    i.days_on_hand,
    ROUND(i.on_hand_qty / NULLIF(i.safety_stock_qty / 7.0, 0), 1) AS days_of_inventory,
    i.turnover_ratio, i.obsolescence_risk_pct, i.reorder_point, i.safety_stock_qty, i.carrying_cost_usd_daily
FROM ZERO_TO_ONE_CHAIN.L5_CORE.FACT_INVENTORY i
LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_PLANT p ON p.plant_id = i.plant_code
LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_PART pt ON pt.part_id = i.material_number;

create or replace view ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_LANDED_COST(
	PO_DATE,
	PO_MONTH,
	SUPPLIER_ID,
	SUPPLIER_NAME,
	SUPPLIER_REGION,
	SUPPLIER_COUNTRY,
	PLANT_CODE,
	MATERIAL_NUMBER,
	MATERIAL_GROUP,
	ORDERED_QTY,
	UNIT_PRICE_USD,
	EXTENDED_PRICE_USD,
	FREIGHT_COST_USD,
	DUTY_COST_USD,
	HANDLING_COST_USD,
	LANDED_COST_USD,
	LANDED_COST_PER_UNIT_USD,
	IS_ON_TIME,
	IS_OTIF
) as
SELECT
    po.po_date,
    DATE_TRUNC('MONTH', po.po_date) AS po_month,
    po.supplier_id,
    s.supplier_name,
    s.region AS supplier_region,
    s.country AS supplier_country,
    po.plant_code,
    po.material_number,
    po.material_group,
    po.ordered_qty,
    po.unit_price_usd,
    po.extended_price_usd,
    po.freight_cost_usd,
    po.duty_cost_usd,
    po.handling_cost_usd,
    -- Landed Cost = unit cost + freight + duty + handling (the ONE definition)
    po.landed_cost_usd,
    CASE WHEN po.ordered_qty > 0
         THEN ROUND(po.landed_cost_usd / po.ordered_qty, 2)
         ELSE NULL
    END AS landed_cost_per_unit_usd,
    po.is_on_time,
    po.is_otif
FROM ZERO_TO_ONE_CHAIN.L5_CORE.FACT_PURCHASE_ORDERS po
LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_SUPPLIER s ON s.supplier_id = po.supplier_id;

create or replace view ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_OTD(
	ORDER_NUMBER,
	ORDER_DATE,
	ORDER_MONTH,
	ORDER_QUARTER,
	CUSTOMER_ID,
	CUSTOMER_NAME,
	CUSTOMER_REGION,
	INDUSTRY,
	SEGMENT,
	SERVICE_TIER,
	PLANT_CODE,
	PLANT_NAME,
	PLANT_REGION,
	MATERIAL_NUMBER,
	SHIPPING_METHOD,
	CHANNEL,
	SERVICE_LEVEL,
	PRIORITY,
	IS_DELIVERED,
	IS_ON_TIME,
	IS_IN_FULL,
	IS_OTIF,
	FILL_RATE_PCT,
	DELIVERY_VARIANCE_DAYS,
	COMMITTED_DELIVERY_DATE,
	ACTUAL_DELIVERY_DATE,
	ORDERED_QTY,
	DELIVERED_QTY,
	NET_VALUE_USD
) COMMENT='Canonical delivery metrics. OTD/OTIF/Fill Rate measured on delivered lines only (IS_DELIVERED = TRUE).'
 as
SELECT
    o.order_number, o.order_date,
    DATE_TRUNC('MONTH', o.order_date) AS order_month,
    DATE_TRUNC('QUARTER', o.order_date) AS order_quarter,
    o.customer_id, c.customer_name, c.region AS customer_region, c.industry, c.segment, c.service_tier,
    o.plant_code, p.plant_name, p.region AS plant_region,
    o.material_number, o.shipping_method, o.channel, o.service_level, o.priority,
    (o.actual_delivery_date IS NOT NULL) AS is_delivered,
    IFF(o.actual_delivery_date IS NOT NULL, o.is_on_time, NULL) AS is_on_time,
    IFF(o.actual_delivery_date IS NOT NULL, o.is_in_full, NULL) AS is_in_full,
    IFF(o.actual_delivery_date IS NOT NULL, o.is_otif, NULL) AS is_otif,
    IFF(o.actual_delivery_date IS NOT NULL, o.fill_rate_pct, NULL) AS fill_rate_pct,
    o.delivery_variance_days, o.committed_delivery_date, o.actual_delivery_date,
    o.ordered_qty, o.delivered_qty, o.net_value_usd
FROM ZERO_TO_ONE_CHAIN.L5_CORE.FACT_ORDERS o
LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_CUSTOMER c ON c.customer_id = o.customer_id
LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_PLANT p ON p.plant_id = o.plant_code;

create or replace view ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_SUPPLIER_DELIVERY(
	SUPPLIER_ID,
	SUPPLIER_NAME,
	REGION,
	TIER,
	DUAL_SOURCE_AVAILABLE,
	RECEIVED_LINES,
	OTD_PCT,
	OTD_90D_PCT,
	OTD_PRIOR_PCT,
	AVG_DAYS_LATE,
	SPEND_USD_MM,
	REJECT_RATE_PCT
) COMMENT='Supplier inbound delivery performance from received PO lines, last 90 days vs prior'
 as
SELECT po.supplier_id, s.supplier_name, s.region, s.tier, s.dual_source_available,
  COUNT_IF(po.actual_delivery_date IS NOT NULL) AS received_lines,
  ROUND(AVG(IFF(po.actual_delivery_date IS NOT NULL, IFF(po.is_on_time,1,0), NULL))*100,1) AS otd_pct,
  ROUND(AVG(IFF(po.actual_delivery_date >= DATEADD(DAY,-90,'2026-10-05'::DATE), IFF(po.is_on_time,1,0), NULL))*100,1) AS otd_90d_pct,
  ROUND(AVG(IFF(po.actual_delivery_date < DATEADD(DAY,-90,'2026-10-05'::DATE), IFF(po.is_on_time,1,0), NULL))*100,1) AS otd_prior_pct,
  ROUND(AVG(IFF(po.actual_delivery_date IS NOT NULL AND NOT po.is_on_time, po.delivery_variance_days, NULL)),1) AS avg_days_late,
  ROUND(SUM(po.landed_cost_usd)/1e6,2) AS spend_usd_mm,
  ROUND(DIV0(SUM(po.rejected_qty), SUM(po.ordered_qty))*100,2) AS reject_rate_pct
FROM ZERO_TO_ONE_CHAIN.L5_CORE.FACT_PURCHASE_ORDERS po
LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_SUPPLIER s ON s.supplier_id = po.supplier_id
WHERE po.supplier_id IS NOT NULL AND po.ordered_qty > 0
GROUP BY 1,2,3,4,5;

create or replace view ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_SUPPLIER_RISK(
	SUPPLIER_ID,
	SUPPLIER_NAME,
	REGION,
	COUNTRY,
	TIER,
	PRIMARY_CATEGORY,
	ANNUAL_SPEND_USD_MM,
	LEAD_TIME_DAYS,
	OTD_PCT,
	DEFECT_PPM,
	FINANCIAL_RISK_SCORE,
	GEOPOLITICAL_RISK_SCORE,
	QUALITY_SCORE,
	DELIVERY_RELIABILITY_PCT,
	SUSTAINABILITY_SCORE,
	ESG_COMPLIANCE_STATUS,
	CONCENTRATION_RISK,
	BLENDED_RISK_SCORE,
	DUAL_SOURCE_AVAILABLE,
	LAST_AUDIT_RESULT,
	SUPPLIER_RISK_SCORE
) as
SELECT
    s.supplier_id,
    s.supplier_name,
    s.region,
    s.country,
    s.tier,
    s.primary_category,
    s.annual_spend_usd_mm,
    s.lead_time_days,
    s.otd_pct,
    s.defect_ppm,
    s.financial_risk_score,
    s.geopolitical_risk_score,
    s.quality_score,
    s.delivery_reliability_pct,
    s.sustainability_score,
    s.esg_compliance_status,
    s.concentration_risk,
    s.blended_risk_score,
    s.dual_source_available,
    s.last_audit_result,
    -- Weighted supplier risk score (the ONE definition)
    ROUND(
        (COALESCE(100 - s.otd_pct, 50)) * 0.25 +                     -- OTD trend
        (COALESCE(s.lead_time_days, 30) / 120 * 100) * 0.20 +         -- Lead time variance proxy
        (COALESCE(s.defect_ppm, 15) / 30 * 100) * 0.15 +              -- Defect rate
        (COALESCE(s.financial_risk_score, 3) / 5 * 100) * 0.20 +      -- Financial risk
        (COALESCE(s.geopolitical_risk_score, 3) / 5 * 100) * 0.10 +   -- Geopolitical risk
        (CASE WHEN s.concentration_risk = 'Critical' THEN 100
              WHEN s.concentration_risk = 'High' THEN 75
              WHEN s.concentration_risk = 'Medium' THEN 50
              ELSE 25 END) * 0.10                                       -- Concentration
    , 2) AS supplier_risk_score
FROM ZERO_TO_ONE_CHAIN.L5_CORE.DIM_SUPPLIER s;

CREATE OR REPLACE PROCEDURE ZERO_TO_ONE_CHAIN.L6_SEMANTIC.SP_REFRESH_CONSISTENCY()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS 'BEGIN
    DELETE FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.CONSISTENCY_PROOF;
    INSERT INTO ZERO_TO_ONE_CHAIN.L6_SEMANTIC.CONSISTENCY_PROOF (question, metric_name, planner_result, procurement_result, logistics_result, all_match)
    WITH m AS (
      SELECT ''What is our on-time delivery rate?'' q, ''OTD %'' n, ROUND(AVG(IFF(is_on_time,1,0))*100,2) v FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_OTD WHERE is_delivered
      UNION ALL SELECT ''What is our OTIF rate?'', ''OTIF %'', ROUND(AVG(IFF(is_otif,1,0))*100,2) FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_OTD WHERE is_delivered
      UNION ALL SELECT ''What is our fill rate?'', ''Fill Rate %'', ROUND(AVG(fill_rate_pct),2) FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_OTD WHERE is_delivered
      UNION ALL SELECT ''What is the average supplier risk score?'', ''Supplier Risk'', ROUND(AVG(supplier_risk_score),2) FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_SUPPLIER_RISK
      UNION ALL SELECT ''What is the average landed cost per unit?'', ''Landed Cost / Unit ($)'', ROUND(AVG(landed_cost_per_unit_usd),2) FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_LANDED_COST WHERE landed_cost_per_unit_usd > 0
      UNION ALL SELECT ''What are the average days of inventory?'', ''Days of Inventory'', ROUND(AVG(days_of_inventory),2) FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_INVENTORY
    )
    SELECT q, n, v, v, v, TRUE FROM m;
    RETURN ''Consistency proof refreshed'';
END';
