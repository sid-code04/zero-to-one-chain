-- ============================================================
-- 98_healthcheck.sql — Verify entire build
-- Zero to One Chain · Supply Chain Decision Twin
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE ZERO_TO_ONE_CHAIN;
USE WAREHOUSE Z21_WH;

-- Layer 1: Raw table counts
SELECT 'L1_INGESTION' AS layer, TABLE_NAME, ROW_COUNT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'L1_INGESTION' ORDER BY TABLE_NAME;

-- Layer 2: Dynamic table counts
SELECT 'L2_STAGE' AS layer, TABLE_NAME, ROW_COUNT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'L2_STAGE' ORDER BY TABLE_NAME;

-- Layer 3: DQ quarantine
SELECT 'L3_VALIDATE' AS layer, COUNT(*) AS quarantine_issues
FROM L3_VALIDATE.DQ_QUARANTINE WHERE resolved_at IS NULL;

-- Layer 4: Harmonization
SELECT 'L4_HARMONIZE' AS layer,
    (SELECT COUNT(*) FROM L4_HARMONIZE.XWALK_VENDOR_SUPPLIER) AS crosswalk_rows,
    (SELECT COUNT(*) FROM L4_HARMONIZE.GOLDEN_SUPPLIERS) AS golden_rows;

-- Layer 5: Ontology
SELECT 'L5_CORE' AS layer, relationship, COUNT(*) AS edge_count
FROM L5_CORE.ONTOLOGY_EDGES GROUP BY relationship;

-- Layer 6: Semantic views
SHOW VIEWS IN SCHEMA L6_SEMANTIC;

-- Layer 7: Agent
SHOW AGENTS IN SCHEMA L7_INTELLIGENCE;

-- Layer 8: Recommendations
SELECT 'L8_ACTION' AS layer,
    (SELECT COUNT(*) FROM L8_ACTION.RECOMMENDATIONS) AS recommendations,
    (SELECT COUNT(*) FROM L8_ACTION.DECISION_AUDIT) AS audit_entries;

-- Governance: Policies
SHOW MASKING POLICIES IN SCHEMA GOVERNANCE;
SHOW ROW ACCESS POLICIES IN SCHEMA GOVERNANCE;

-- Roles
SHOW ROLES LIKE 'Z21%';

SELECT '✅ Healthcheck complete' AS status;
