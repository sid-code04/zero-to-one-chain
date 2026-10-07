-- L7 Intelligence: what-if views, forecast and anomaly inputs, document search
-- Reference DDL extracted from the deployed DEV database ZERO_TO_ONE_CHAIN (GET_DDL), so it matches what is running.
-- Other environments are built from DEV by SP_DEPLOY_ENVIRONMENT (see 90_release.sql).
-- Agents: cortex_project/*.agent.yaml. Assistant tools: 93_assistant.sql. ML models: 02_ml_models.sql.
USE DATABASE ZERO_TO_ONE_CHAIN;

create or replace TABLE ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.OTD_FORECAST_RESULTS (
	"status" VARCHAR(16777216)
);

create or replace TABLE ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.SUPPLY_CHAIN_DOCUMENTS (
	DOC_ID NUMBER(38,0) autoincrement start 1 increment 1 noorder,
	DOC_TYPE VARCHAR(16777216) NOT NULL,
	TITLE VARCHAR(16777216) NOT NULL,
	SUPPLIER_ID VARCHAR(16777216),
	SUPPLIER_NAME VARCHAR(16777216),
	CONTENT VARCHAR(16777216) NOT NULL,
	EFFECTIVE_DATE DATE,
	EXPIRY_DATE DATE,
	TAGS ARRAY,
	CREATED_AT TIMESTAMP_LTZ(9) DEFAULT CURRENT_TIMESTAMP()
);

create or replace view ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.VW_INVENTORY_ANOMALIES(
	SNAPSHOT_DATE,
	PLANT_CODE,
	PLANT_NAME,
	REGION,
	MATERIAL_NUMBER,
	PART_NAME,
	INVENTORY_VALUE_USD,
	DAYS_ON_HAND,
	STOCK_STATUS,
	VALUE_ZSCORE,
	DOH_ZSCORE,
	ANOMALY_TYPE
) as
-- Inventory anomalies: z-score > 2 on value or days-on-hand per plant/part, plus stockout and below-safety rows.
WITH stats AS (
    SELECT
        plant_code,
        material_number,
        AVG(inventory_value_usd) AS avg_value,
        STDDEV(inventory_value_usd) AS stddev_value,
        AVG(days_on_hand) AS avg_doh,
        STDDEV(days_on_hand) AS stddev_doh
    FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_INVENTORY
    GROUP BY plant_code, material_number
    HAVING COUNT(*) >= 3
),
scored AS (
    SELECT
        i.snapshot_date,
        i.plant_code,
        p.plant_name,
        p.region,
        i.material_number,
        pt.part_name,
        i.inventory_value_usd,
        i.days_on_hand,
        i.stock_status,
        ROUND(ABS(i.inventory_value_usd - s.avg_value) / NULLIF(s.stddev_value, 0), 2) AS value_zscore,
        ROUND(ABS(i.days_on_hand - s.avg_doh) / NULLIF(s.stddev_doh, 0), 2) AS doh_zscore,
        CASE
            WHEN ABS(i.inventory_value_usd - s.avg_value) / NULLIF(s.stddev_value, 0) > 2 THEN 'VALUE_ANOMALY'
            WHEN ABS(i.days_on_hand - s.avg_doh) / NULLIF(s.stddev_doh, 0) > 2 THEN 'DOH_ANOMALY'
            WHEN i.stock_status = 'STOCKOUT' THEN 'STOCKOUT'
            WHEN i.stock_status = 'BELOW_SAFETY' THEN 'BELOW_SAFETY'
            ELSE 'NORMAL'
        END AS anomaly_type
    FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_INVENTORY i
    JOIN stats s ON s.plant_code = i.plant_code AND s.material_number = i.material_number
    LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_PLANT p ON p.plant_id = i.plant_code
    LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_PART pt ON pt.part_id = i.material_number
)
SELECT * FROM scored WHERE anomaly_type != 'NORMAL';

create or replace view ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.VW_INVENTORY_ANOMALY_INPUT(
	DS,
	SERIES,
	INVENTORY_VALUE
) as
SELECT
    SNAPSHOT_DATE AS ds,
    PLANT_CODE AS series,
    SUM(INVENTORY_VALUE_USD) AS inventory_value
FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_INVENTORY
GROUP BY SNAPSHOT_DATE, PLANT_CODE
ORDER BY PLANT_CODE, SNAPSHOT_DATE;

create or replace view ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.VW_OTD_MONTHLY_SERIES(
	DS,
	OTD_PCT,
	OTIF_PCT,
	ORDER_COUNT,
	TOTAL_VALUE
) as
SELECT
    ORDER_MONTH AS ds,
    ROUND(AVG(CASE WHEN IS_ON_TIME THEN 1 ELSE 0 END) * 100, 2) AS otd_pct,
    ROUND(AVG(CASE WHEN IS_OTIF THEN 1 ELSE 0 END) * 100, 2) AS otif_pct,
    COUNT(*) AS order_count,
    ROUND(SUM(NET_VALUE_USD), 0) AS total_value
FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_OTD
WHERE ORDER_MONTH IS NOT NULL
GROUP BY ORDER_MONTH
ORDER BY ORDER_MONTH;

create or replace view ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.VW_OTD_SIMPLE_SERIES(
	DS,
	OTD_PCT
) as
SELECT
    ORDER_MONTH AS ds,
    ROUND(AVG(CASE WHEN IS_ON_TIME THEN 1 ELSE 0 END) * 100, 2) AS otd_pct
FROM ZERO_TO_ONE_CHAIN.L6_SEMANTIC.VW_METRIC_OTD
WHERE ORDER_MONTH IS NOT NULL
GROUP BY ORDER_MONTH
ORDER BY ORDER_MONTH;

create or replace view ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.VW_WHATIF_CUSTOMER_IMPACT(
	SUPPLIER_ID,
	CUSTOMER_ID,
	CUSTOMER_NAME,
	CUSTOMER_REGION,
	INDUSTRY,
	SERVICE_TIER,
	SLA_CONTRACT,
	OPEN_ORDERS,
	REVENUE_AT_RISK_USD,
	EARLIEST_COMMITMENT,
	AFFECTED_PARTS
) as
-- Disruption simulator: supplier -> parts it is primary source for -> open customer orders needing them.
-- One row per supplier and customer, with revenue at risk and the earliest committed delivery date.
WITH sp AS (
  SELECT DISTINCT primary_vendor_code AS supplier_id, material_number
  FROM ZERO_TO_ONE_CHAIN.L1_INGESTION.RAW_ERP_MATERIALS
)
SELECT sp.supplier_id, o.customer_id, c.customer_name, c.region AS customer_region, c.industry,
  c.service_tier, c.sla_contract,
  COUNT(DISTINCT o.order_number) AS open_orders,
  ROUND(SUM(o.net_value_usd),2) AS revenue_at_risk_usd,
  MIN(o.committed_delivery_date) AS earliest_commitment,
  COUNT(DISTINCT o.material_number) AS affected_parts
FROM sp
JOIN ZERO_TO_ONE_CHAIN.L5_CORE.FACT_ORDERS o
  ON o.material_number = sp.material_number AND o.actual_delivery_date IS NULL AND o.order_status <> 'CANCELLED'
LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_CUSTOMER c ON c.customer_id = o.customer_id
GROUP BY 1,2,3,4,5,6,7;

create or replace view ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.VW_WHATIF_SUPPLIER_DISRUPTION(
	SUPPLIER_ID,
	SUPPLIER_NAME,
	REGION,
	TIER,
	BLENDED_RISK_SCORE,
	DUAL_SOURCE_AVAILABLE,
	AFFECTED_PARTS,
	AFFECTED_PLANTS,
	AFFECTED_ORDERS,
	AFFECTED_CUSTOMERS,
	TOTAL_REVENUE_AT_RISK_USD,
	EARLIEST_COMMITMENT
) COMMENT='Blast radius: supplier -> parts it sources -> open customer orders for those parts'
 as
WITH sp AS (
  SELECT DISTINCT primary_vendor_code AS supplier_id, material_number
  FROM ZERO_TO_ONE_CHAIN.L1_INGESTION.RAW_ERP_MATERIALS
), open_orders AS (
  SELECT order_number, customer_id, plant_code, material_number, net_value_usd, committed_delivery_date
  FROM ZERO_TO_ONE_CHAIN.L5_CORE.FACT_ORDERS
  WHERE actual_delivery_date IS NULL AND order_status <> 'CANCELLED'
)
SELECT
  sp.supplier_id, s.supplier_name, s.region, s.tier, s.blended_risk_score, s.dual_source_available,
  COUNT(DISTINCT sp.material_number) AS affected_parts,
  COUNT(DISTINCT o.plant_code) AS affected_plants,
  COUNT(DISTINCT o.order_number) AS affected_orders,
  COUNT(DISTINCT o.customer_id) AS affected_customers,
  ROUND(COALESCE(SUM(o.net_value_usd),0),2) AS total_revenue_at_risk_usd,
  MIN(o.committed_delivery_date) AS earliest_commitment
FROM sp
LEFT JOIN open_orders o ON o.material_number = sp.material_number
LEFT JOIN ZERO_TO_ONE_CHAIN.L5_CORE.DIM_SUPPLIER s ON s.supplier_id = sp.supplier_id
GROUP BY 1,2,3,4,5,6;

create or replace cortex search service ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.SC_DOCUMENT_SEARCH
	ON CONTENT
	attributes DOC_TYPE,TITLE,SUPPLIER_NAME
	warehouse='Z21_WH'
	target_lag='1 hour'
	refresh_mode=INCREMENTAL
	as (
    SELECT
        doc_id::VARCHAR AS doc_id,
        doc_type,
        title,
        supplier_id,
        supplier_name,
        content,
        effective_date::VARCHAR AS effective_date,
        expiry_date::VARCHAR AS expiry_date
    FROM ZERO_TO_ONE_CHAIN.L7_INTELLIGENCE.SUPPLY_CHAIN_DOCUMENTS
);
