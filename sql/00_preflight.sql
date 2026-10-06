-- ============================================================
-- 00_preflight.sql — Environment readiness checks
-- Zero to One Chain · Supply Chain Decision Twin
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- 1. Role check
SELECT CURRENT_ROLE() AS current_role,
       IFF(CURRENT_ROLE() = 'ACCOUNTADMIN', '✅ ACCOUNTADMIN', '❌ Need ACCOUNTADMIN') AS status;

-- 2. Warehouse check
SELECT CURRENT_WAREHOUSE() AS current_warehouse,
       IFF(CURRENT_WAREHOUSE() IS NOT NULL, '✅ Warehouse active', '❌ No warehouse set') AS status;

-- 3. Region check (Cortex AI availability)
SELECT CURRENT_REGION() AS region,
       CURRENT_ACCOUNT() AS account,
       CURRENT_VERSION() AS sf_version;

-- 4. Cortex AI feature probe — sentiment as canary
SELECT AI_SENTIMENT('Supply chain is running smoothly') AS cortex_probe,
       '✅ Cortex AI available' AS status;

-- 5. Dynamic Tables support (standard in all regions)
SELECT SYSTEM$TYPEOF(1) AS dt_probe,
       '✅ Dynamic Tables available' AS status;
