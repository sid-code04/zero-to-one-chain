-- Governance: masking and row access policies, classification tags
-- Reference DDL extracted from the deployed DEV database ZERO_TO_ONE_CHAIN (GET_DDL), so it matches what is running.
-- Other environments are built from DEV by SP_DEPLOY_ENVIRONMENT (see 90_release.sql).
USE DATABASE ZERO_TO_ONE_CHAIN;

create or replace tag ZERO_TO_ONE_CHAIN.GOVERNANCE.DATA_DOMAIN  allowed_values  'SUPPLIER' , 'CUSTOMER' , 'INVENTORY' , 'LOGISTICS' , 'PROCUREMENT' , 'QUALITY' ;

create or replace tag ZERO_TO_ONE_CHAIN.GOVERNANCE.DATA_FRESHNESS  allowed_values  'REAL_TIME' , 'HOURLY' , 'DAILY' , 'WEEKLY' ;

create or replace tag ZERO_TO_ONE_CHAIN.GOVERNANCE.DATA_SENSITIVITY  allowed_values  'PII' , 'FINANCIAL' , 'OPERATIONAL' , 'PUBLIC' ;

create or replace tag ZERO_TO_ONE_CHAIN.GOVERNANCE.METRIC_OWNER  allowed_values  'PLANNING' , 'PROCUREMENT' , 'LOGISTICS' , 'SHARED' ;

create or replace masking policy ZERO_TO_ONE_CHAIN.GOVERNANCE.MASK_CONTACT_EMAIL as (VAL VARCHAR) 
returns VARCHAR ->
CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'Z21_ADMIN') THEN val
        ELSE '***@masked.com'
    END
;

create or replace masking policy ZERO_TO_ONE_CHAIN.GOVERNANCE.MASK_SUPPLIER_COST as (VAL NUMBER(10,2)) 
returns NUMBER(10,2) ->
CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'Z21_ADMIN', 'Z21_PROCUREMENT') THEN val
        ELSE -1  -- masked value
    END
;

create or replace row access policy ZERO_TO_ONE_CHAIN.GOVERNANCE.RAP_REGION_ACCESS as (REGION_COL VARCHAR) 
returns BOOLEAN ->
CURRENT_ROLE() IN ('ACCOUNTADMIN', 'Z21_ADMIN')
    OR (CURRENT_ROLE() = 'Z21_PLANNER')  -- planners see all regions
    OR (CURRENT_ROLE() = 'Z21_PROCUREMENT')  -- procurement sees all regions
    OR (CURRENT_ROLE() = 'Z21_LOGISTICS' AND region_col IN ('AMERICAS', 'EMEA'))
;
