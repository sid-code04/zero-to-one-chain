-- ============================================================
-- L1_ingestion/01_raw_dimensions.sql
-- Dimension tables: Suppliers, Parts, Plants, Customers, Carriers
-- Each source system uses its own naming conventions
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE ZERO_TO_ONE_CHAIN;
USE SCHEMA L1_INGESTION;
USE WAREHOUSE Z21_WH;

-- ============================================================
-- ERP SOURCE: Suppliers (SRM system calls them "vendors")
-- ============================================================
CREATE OR REPLACE TABLE RAW_ERP_VENDORS AS
WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'V-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4()), 6, '0') AS vendor_code,
        ARRAY_CONSTRUCT(
            'Acme Manufacturing', 'GlobalParts Inc', 'PrecisionCast Ltd', 'SteelWorks Corp',
            'TechComponents AG', 'Pacific Materials', 'Atlas Fasteners', 'NovaChem Industries',
            'Pinnacle Plastics', 'MetalForm Solutions', 'ElectroParts GmbH', 'OceanFreight Supplies',
            'GreenEnergy Parts', 'AeroComp Systems', 'MicroPrecision Co', 'TitanAlloys LLC',
            'FlexiPack Group', 'DiamondCut Tools', 'CeramTech Intl', 'BioMaterials Inc'
        )[MOD(rn, 20)]::STRING || ' - ' || LPAD(rn::STRING, 3, '0') AS vendor_name,
        ARRAY_CONSTRUCT('APAC','EMEA','AMERICAS','APAC','EMEA','AMERICAS')[MOD(rn, 6)]::STRING AS vendor_region,
        ARRAY_CONSTRUCT('CN','DE','US','IN','JP','MX','KR','BR','TW','VN','TH','GB','FR','IT','CA')[MOD(rn, 15)]::STRING AS country_code,
        ARRAY_CONSTRUCT('Tier 1','Tier 1','Tier 2','Tier 2','Tier 3')[MOD(rn, 5)]::STRING AS vendor_tier,
        ARRAY_CONSTRUCT('Active','Active','Active','Active','Probation','Inactive')[MOD(rn, 6)]::STRING AS vendor_status,
        ARRAY_CONSTRUCT('Raw Materials','Components','Sub-assemblies','Packaging','MRO','Chemicals','Electronics')[MOD(rn, 7)]::STRING AS primary_category,
        ARRAY_CONSTRUCT('ISO 9001','ISO 14001','ISO 9001, ISO 14001','IATF 16949','None')[MOD(rn, 5)]::STRING AS certifications,
        DATEADD(DAY, -UNIFORM(365, 3650, RANDOM()), CURRENT_DATE()) AS onboarding_date,
        UNIFORM(1, 100, RANDOM())::NUMBER(10,2) AS annual_spend_usd_mm,
        UNIFORM(1, 50, RANDOM()) AS avg_lead_time_days,
        UNIFORM(50, 100, RANDOM())::NUMBER(5,2) AS historical_otd_pct,
        UNIFORM(1, 30, RANDOM())::NUMBER(5,2) AS defect_rate_ppm,
        UNIFORM(1, 5, RANDOM())::NUMBER(3,1) AS financial_risk_score,
        UNIFORM(1, 5, RANDOM())::NUMBER(3,1) AS geopolitical_risk_score,
        ARRAY_CONSTRUCT('NET 30','NET 45','NET 60','NET 90','COD')[MOD(rn, 5)]::STRING AS payment_terms,
        ARRAY_CONSTRUCT('USD','EUR','CNY','JPY','INR','MXN','KRW','BRL')[MOD(rn, 8)]::STRING AS local_currency,
        UNIFORM(100, 999, RANDOM())::STRING || '-' || UNIFORM(100, 999, RANDOM())::STRING || '-' || UNIFORM(1000, 9999, RANDOM())::STRING AS contact_phone,
        LOWER(REPLACE(SPLIT_PART(vendor_name, ' ', 1), '-', '')) || '@vendor.example.com' AS contact_email,
        ARRAY_CONSTRUCT('Small','Medium','Medium','Large','Large','Enterprise')[MOD(rn, 6)]::STRING AS company_size,
        UNIFORM(50, 50000, RANDOM()) AS employee_count,
        UNIFORM(1, 20, RANDOM()) AS num_plants,
        ARRAY_CONSTRUCT('Yes','Yes','No','Yes','No')[MOD(rn, 5)]::STRING AS dual_source_available,
        DATEADD(DAY, -UNIFORM(1, 90, RANDOM()), CURRENT_DATE()) AS last_audit_date,
        ARRAY_CONSTRUCT('Pass','Pass','Pass','Conditional','Fail')[MOD(rn, 5)]::STRING AS last_audit_result,
        CURRENT_TIMESTAMP() AS _loaded_at,
        'ERP_SYSTEM' AS _source_system
    FROM TABLE(GENERATOR(ROWCOUNT => 500))
)
SELECT * FROM base;

-- ============================================================
-- SRM SOURCE: Suppliers (different naming, overlapping data)
-- ============================================================
CREATE OR REPLACE TABLE RAW_SRM_SUPPLIERS AS
WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'SUP' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4()), 5, '0') AS supplier_id,
        'V-' || LPAD(CEIL(rn * 1.1)::INT, 6, '0') AS erp_vendor_ref,  -- deliberately misaligned
        ARRAY_CONSTRUCT(
            'Acme Mfg', 'GlobalParts', 'PrecisionCast', 'SteelWorks',
            'TechComp AG', 'Pacific Mat', 'Atlas Fast', 'NovaChem',
            'Pinnacle Plast', 'MetalForm Sol', 'ElectroParts', 'OceanFreight',
            'GreenEnergy', 'AeroComp', 'MicroPrec', 'TitanAlloys',
            'FlexiPack', 'DiamondCut', 'CeramTech', 'BioMat Inc'
        )[MOD(rn, 20)]::STRING || ' #' || rn::STRING AS supplier_name,  -- different name format
        ARRAY_CONSTRUCT('Asia-Pacific','Europe-ME-Africa','North America','South America','Asia-Pacific','Europe-ME-Africa')[MOD(rn, 6)]::STRING AS region_name,  -- different region names
        UNIFORM(60, 99, RANDOM())::NUMBER(5,2) AS quality_score,
        UNIFORM(50, 99, RANDOM())::NUMBER(5,2) AS delivery_reliability_pct,
        UNIFORM(1, 10, RANDOM())::NUMBER(3,1) AS responsiveness_score,
        UNIFORM(1, 10, RANDOM())::NUMBER(3,1) AS innovation_score,
        UNIFORM(1, 10, RANDOM())::NUMBER(3,1) AS sustainability_score,
        UNIFORM(0, 100, RANDOM())::NUMBER(5,2) AS cost_competitiveness_idx,
        ARRAY_CONSTRUCT('Strategic','Preferred','Approved','Conditional','Blocked')[MOD(rn, 5)]::STRING AS relationship_tier,
        DATEADD(DAY, -UNIFORM(30, 365, RANDOM()), CURRENT_DATE()) AS last_performance_review,
        DATEADD(DAY, -UNIFORM(1, 60, RANDOM()), CURRENT_DATE()) AS last_order_date,
        UNIFORM(1, 500, RANDOM()) AS open_pos_count,
        UNIFORM(0, 50, RANDOM())::NUMBER(10,2) AS open_pos_value_usd_mm,
        ARRAY_CONSTRUCT('Compliant','Compliant','Non-compliant','Under Review','Exempt')[MOD(rn, 5)]::STRING AS esg_compliance_status,
        UNIFORM(1, 100, RANDOM())::NUMBER(5,2) AS carbon_intensity_score,
        ARRAY_CONSTRUCT('Low','Medium','Medium','High','Critical')[MOD(rn, 5)]::STRING AS concentration_risk,
        UNIFORM(0, 100, RANDOM())::NUMBER(5,2) AS pct_of_category_spend,
        ARRAY_CONSTRUCT('Yes','No','Yes','No','Yes')[MOD(rn, 5)]::STRING AS backup_supplier_exists,
        CURRENT_TIMESTAMP() AS _loaded_at,
        'SRM_SYSTEM' AS _source_system
    FROM TABLE(GENERATOR(ROWCOUNT => 450))  -- deliberately different count
)
SELECT * FROM base;

-- ============================================================
-- PARTS / ITEMS (ERP calls them "materials")
-- ============================================================
CREATE OR REPLACE TABLE RAW_ERP_MATERIALS AS
WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'MAT-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4()), 7, '0') AS material_number,
        ARRAY_CONSTRUCT('Bearing','Shaft','Gear','Pump','Valve','Sensor','Housing','Bracket',
                        'Seal','Connector','Wire Harness','PCB Assembly','Fastener Set','Filter',
                        'Motor','Actuator','Spring','Gasket','Bushing','Coupling')[MOD(rn, 20)]::STRING
            || ' - ' || ARRAY_CONSTRUCT('Type A','Type B','Type C','HD','XL','Compact','Pro','Eco')[MOD(rn, 8)]::STRING AS material_description,
        ARRAY_CONSTRUCT('Raw Material','Component','Sub-assembly','Finished Good','MRO','Packaging')[MOD(rn, 6)]::STRING AS material_type,
        ARRAY_CONSTRUCT('Mechanical','Electrical','Hydraulic','Pneumatic','Electronic','Chemical','Structural')[MOD(rn, 7)]::STRING AS material_group,
        ARRAY_CONSTRUCT('Bearings','Shafts','Gears','Pumps','Valves','Sensors','Housings','Brackets',
                        'Seals','Connectors','Wiring','PCBs','Fasteners','Filters',
                        'Motors','Actuators','Springs','Gaskets','Bushings','Couplings')[MOD(rn, 20)]::STRING AS category,
        ARRAY_CONSTRUCT('Rotating Equipment','Power Transmission','Fluid Control','Electronics','Structural','Consumables')[MOD(rn, 6)]::STRING AS family,
        ARRAY_CONSTRUCT('kg','each','meter','liter','set','box','roll')[MOD(rn, 7)]::STRING AS uom,
        UNIFORM(1, 5000, RANDOM())::NUMBER(10,2) AS standard_cost_usd,
        UNIFORM(0, 50, RANDOM())::NUMBER(5,2) AS weight_kg,
        ARRAY_CONSTRUCT('A','A','B','B','C','C','C')[MOD(rn, 7)]::STRING AS abc_class,
        ARRAY_CONSTRUCT('X','X','Y','Y','Z')[MOD(rn, 5)]::STRING AS xyz_class,
        UNIFORM(1, 90, RANDOM()) AS safety_stock_days,
        UNIFORM(5, 120, RANDOM()) AS lead_time_days,
        UNIFORM(1, 100, RANDOM()) AS min_order_qty,
        UNIFORM(100, 10000, RANDOM()) AS economic_order_qty,
        ARRAY_CONSTRUCT('Active','Active','Active','Discontinued','Phase-out','New')[MOD(rn, 6)]::STRING AS lifecycle_status,
        ARRAY_CONSTRUCT('Yes','No','No','Yes','No')[MOD(rn, 5)]::STRING AS hazardous,
        ARRAY_CONSTRUCT('None','Temperature','Humidity','ESD','Fragile')[MOD(rn, 5)]::STRING AS special_handling,
        ARRAY_CONSTRUCT('Yes','Yes','No')[MOD(rn, 3)]::STRING AS dual_sourced,
        'V-' || LPAD(UNIFORM(1, 500, RANDOM()), 6, '0') AS primary_vendor_code,
        'V-' || LPAD(UNIFORM(1, 500, RANDOM()), 6, '0') AS secondary_vendor_code,
        DATEADD(DAY, -UNIFORM(30, 3650, RANDOM()), CURRENT_DATE()) AS created_date,
        DATEADD(DAY, -UNIFORM(1, 90, RANDOM()), CURRENT_DATE()) AS last_modified_date,
        CURRENT_TIMESTAMP() AS _loaded_at,
        'ERP_SYSTEM' AS _source_system
    FROM TABLE(GENERATOR(ROWCOUNT => 2000))
)
SELECT * FROM base;

-- ============================================================
-- PLANTS / FACILITIES
-- ============================================================
CREATE OR REPLACE TABLE RAW_ERP_PLANTS AS
WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'PLT-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4()), 4, '0') AS plant_code,
        ARRAY_CONSTRUCT(
            'Detroit Assembly','Shanghai Hub','Munich Center','Chennai Works','Guadalajara Plant',
            'Sao Paulo Ops','Tokyo Precision','Seoul Tech','Taipei Foundry','Bangkok Assembly',
            'Ho Chi Minh Plant','London Distribution','Paris Logistics','Milan Components','Toronto Warehouse',
            'Melbourne Hub','Hyderabad IT Park','Bangalore Factory','Pune Assembly','Delhi Distribution',
            'Shenzhen Electronics','Guangzhou Plastics','Nagoya Auto','Busan Shipyard','Hanoi Textiles',
            'Jakarta Assembly','Manila Ops','Singapore Hub','Dubai Logistics','Johannesburg Distribution',
            'Lagos Warehouse','Nairobi Hub','Cairo Assembly','Istanbul Components','Warsaw Logistics',
            'Prague Electronics','Budapest Chemicals','Bucharest Assembly','Athens Logistics','Stockholm Precision',
            'Helsinki Tech','Oslo Green','Copenhagen Smart','Amsterdam Distribution','Brussels Components',
            'Zurich Precision','Vienna Assembly','Barcelona Logistics','Madrid Components','Lisbon Hub'
        )[MOD(rn, 50)]::STRING AS plant_name,
        ARRAY_CONSTRUCT('US','CN','DE','IN','MX','BR','JP','KR','TW','TH',
                        'VN','GB','FR','IT','CA','AU','IN','IN','IN','IN',
                        'CN','CN','JP','KR','VN','ID','PH','SG','AE','ZA',
                        'NG','KE','EG','TR','PL','CZ','HU','RO','GR','SE',
                        'FI','NO','DK','NL','BE','CH','AT','ES','ES','PT')[MOD(rn, 50)]::STRING AS country,
        ARRAY_CONSTRUCT('AMERICAS','APAC','EMEA','APAC','AMERICAS','AMERICAS','APAC','APAC','APAC','APAC',
                        'APAC','EMEA','EMEA','EMEA','AMERICAS','APAC','APAC','APAC','APAC','APAC',
                        'APAC','APAC','APAC','APAC','APAC','APAC','APAC','APAC','EMEA','EMEA',
                        'EMEA','EMEA','EMEA','EMEA','EMEA','EMEA','EMEA','EMEA','EMEA','EMEA',
                        'EMEA','EMEA','EMEA','EMEA','EMEA','EMEA','EMEA','EMEA','EMEA','EMEA')[MOD(rn, 50)]::STRING AS region,
        ARRAY_CONSTRUCT('Assembly','Distribution','Manufacturing','Warehouse','Logistics Hub')[MOD(rn, 5)]::STRING AS plant_type,
        ARRAY_CONSTRUCT('Active','Active','Active','Active','Maintenance')[MOD(rn, 5)]::STRING AS plant_status,
        UNIFORM(50, 5000, RANDOM()) AS headcount,
        UNIFORM(10000, 500000, RANDOM()) AS capacity_sqm,
        UNIFORM(50, 100, RANDOM())::NUMBER(5,2) AS utilization_pct,
        UNIFORM(-90, 90, RANDOM())::NUMBER(8,4) AS latitude,
        UNIFORM(-180, 180, RANDOM())::NUMBER(9,4) AS longitude,
        ARRAY_CONSTRUCT('ISO 9001','ISO 14001','ISO 9001, ISO 14001','IATF 16949','ISO 45001')[MOD(rn, 5)]::STRING AS certifications,
        DATEADD(YEAR, -UNIFORM(1, 40, RANDOM()), CURRENT_DATE()) AS established_date,
        UNIFORM(10, 200, RANDOM())::NUMBER(10,2) AS annual_output_value_usd_mm,
        ARRAY_CONSTRUCT('Automotive','Industrial','Electronics','Consumer','Mixed')[MOD(rn, 5)]::STRING AS primary_sector,
        UNIFORM(1, 50, RANDOM()) AS num_production_lines,
        ARRAY_CONSTRUCT('24/7','2-shift','1-shift','Seasonal')[MOD(rn, 4)]::STRING AS shift_pattern,
        UNIFORM(1, 100, RANDOM())::NUMBER(5,2) AS energy_cost_per_unit,
        ARRAY_CONSTRUCT('Grid','Solar+Grid','Hybrid','Gas','Renewable')[MOD(rn, 5)]::STRING AS energy_source,
        CURRENT_TIMESTAMP() AS _loaded_at,
        'ERP_SYSTEM' AS _source_system
    FROM TABLE(GENERATOR(ROWCOUNT => 50))
)
SELECT * FROM base;

-- ============================================================
-- CUSTOMERS
-- ============================================================
CREATE OR REPLACE TABLE RAW_ERP_CUSTOMERS AS
WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        'CUST-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4()), 6, '0') AS customer_id,
        ARRAY_CONSTRUCT(
            'Automotive Corp','Industrial Solutions','TechBuild Inc','MegaRetail','SmartFactory GmbH',
            'AeroDefense Ltd','HealthTech Systems','EnergyCo','AgriPrime','ConstructionPro',
            'TransportLogic','FoodProcess Inc','PharmaChem','TextileMasters','MiningOps Ltd',
            'TelecomInfra','WaterWorks','ElecGrid Corp','PetroChem','MarineShip Co'
        )[MOD(rn, 20)]::STRING || ' - ' || ARRAY_CONSTRUCT('West','East','North','South','Central')[MOD(rn, 5)]::STRING AS customer_name,
        ARRAY_CONSTRUCT('AMERICAS','EMEA','APAC','AMERICAS','EMEA','APAC')[MOD(rn, 6)]::STRING AS customer_region,
        ARRAY_CONSTRUCT('US','DE','CN','IN','JP','GB','BR','MX','FR','KR','CA','AU','SG','AE','ZA')[MOD(rn, 15)]::STRING AS country,
        ARRAY_CONSTRUCT('Automotive','Industrial','Technology','Retail','Manufacturing',
                        'Aerospace','Healthcare','Energy','Agriculture','Construction')[MOD(rn, 10)]::STRING AS industry,
        ARRAY_CONSTRUCT('Enterprise','Enterprise','Mid-Market','Mid-Market','SMB','SMB')[MOD(rn, 6)]::STRING AS segment,
        ARRAY_CONSTRUCT('Platinum','Gold','Silver','Bronze','Standard')[MOD(rn, 5)]::STRING AS service_tier,
        UNIFORM(1, 500, RANDOM())::NUMBER(10,2) AS annual_revenue_usd_mm,
        UNIFORM(1, 100, RANDOM())::NUMBER(10,2) AS annual_order_value_usd_mm,
        ARRAY_CONSTRUCT('Active','Active','Active','Active','Churned','At Risk')[MOD(rn, 6)]::STRING AS customer_status,
        DATEADD(DAY, -UNIFORM(365, 7300, RANDOM()), CURRENT_DATE()) AS relationship_start_date,
        ARRAY_CONSTRUCT('NET 30','NET 45','NET 60','NET 90','Prepaid')[MOD(rn, 5)]::STRING AS payment_terms,
        ARRAY_CONSTRUCT('USD','EUR','CNY','JPY','GBP','INR','BRL','MXN')[MOD(rn, 8)]::STRING AS billing_currency,
        UNIFORM(1, 50, RANDOM()) AS num_ship_to_locations,
        ARRAY_CONSTRUCT('High','Medium','Medium','Low','Low')[MOD(rn, 5)]::STRING AS credit_risk,
        UNIFORM(1, 10, RANDOM())::NUMBER(3,1) AS nps_score,
        UNIFORM(50, 100, RANDOM())::NUMBER(5,2) AS historical_fill_rate_pct,
        UNIFORM(50, 100, RANDOM())::NUMBER(5,2) AS historical_otd_pct,
        UNIFORM(0, 20, RANDOM()) AS open_complaints,
        ARRAY_CONSTRUCT('Yes','No','Yes','No','Yes')[MOD(rn, 5)]::STRING AS sla_contract,
        UNIFORM(90, 100, RANDOM())::NUMBER(5,2) AS sla_target_otd_pct,
        ARRAY_CONSTRUCT('Direct','Distributor','Online','Hybrid')[MOD(rn, 4)]::STRING AS channel,
        ARRAY_CONSTRUCT('john.doe','jane.smith','mike.wilson','sara.chen','alex.kumar')[MOD(rn, 5)]::STRING || '@customer.example.com' AS primary_contact_email,
        UNIFORM(100, 999, RANDOM())::STRING || '-' || UNIFORM(1000, 9999, RANDOM())::STRING AS primary_contact_phone,
        CURRENT_TIMESTAMP() AS _loaded_at,
        'ERP_SYSTEM' AS _source_system
    FROM TABLE(GENERATOR(ROWCOUNT => 1000))
)
SELECT * FROM base;

SELECT 'Dimension tables created' AS status,
       (SELECT COUNT(*) FROM RAW_ERP_VENDORS) AS vendors,
       (SELECT COUNT(*) FROM RAW_SRM_SUPPLIERS) AS srm_suppliers,
       (SELECT COUNT(*) FROM RAW_ERP_MATERIALS) AS materials,
       (SELECT COUNT(*) FROM RAW_ERP_PLANTS) AS plants,
       (SELECT COUNT(*) FROM RAW_ERP_CUSTOMERS) AS customers;
