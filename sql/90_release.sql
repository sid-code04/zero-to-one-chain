-- ============================================================
-- 90_release.sql - Release pipeline: DEV -> UAT -> PROD
-- Zero to One Chain · Supply Chain Decision Twin
--
--   CALL ZERO_TO_ONE_CHAIN.L8_ACTION.SP_RELEASE('DEV', 'UAT');
--   CALL ZERO_TO_ONE_CHAIN.L8_ACTION.SP_RELEASE('UAT', 'PROD');
--
-- Each release: DQ gate (blocks on any critical issue) -> raw data promotion
-- -> dbt build + tests on the target -> full-stack deploy of every layer
-- (tables, dynamic tables, views, procedures, DMFs, policies, tags, streams,
-- tasks, alerts, Cortex Search, semantic view, agents, ML models, grants),
-- with all references rewritten to the target database. Nothing is cloned.
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- ------------------------------------------------------------
-- SP_DEPLOY_ENVIRONMENT: rebuild the full stack in UAT or PROD
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE ZERO_TO_ONE_CHAIN.L8_ACTION.SP_DEPLOY_ENVIRONMENT(ENV VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
import json
import re

SRC = "ZERO_TO_ONE_CHAIN"
DOLLARS = chr(36) * 2
SKIP_SCHEMAS = {"INFORMATION_SCHEMA", "PUBLIC", "L1_INGESTION", "PUBLIC_L2_STAGE", "PUBLIC_L5_CORE", "DBT_DEPLOY", "DATA_GEN"}
SKIP_PROCS = {"SP_PROMOTE_DEV_TO_UAT", "SP_PROMOTE_UAT_TO_PROD", "SP_DEPLOY_ENVIRONMENT", "SP_RELEASE",
              "SP_PROJECT_CONTROL", "SP_RELEASE_TRAIN", "SP_DECIDE_RELEASE",
              "SP_DEV_FINGERPRINT"}  # control-plane procedures live in DEV only
SKIP_TASKS = {"TASK_RELEASE_TRAIN"}  # the release train runs from DEV only
KEEP_IF_EXISTS = {("L8_ACTION", "RECOMMENDATIONS"), ("L8_ACTION", "DECISION_AUDIT")}
SKIP_TABLES = {("L8_ACTION", "ENVIRONMENT_REGISTRY"), ("L8_ACTION", "RELEASE_TRAIN")}
# GET_DDL drops inner column names for DMF table arguments, so project DMFs are defined explicitly.
DMF_DDL = {
    "DMF_NEGATIVE_COUNT": "(ARG_T TABLE(ARG_C NUMBER)) RETURNS NUMBER AS 'SELECT COUNT_IF(ARG_C < 0) FROM ARG_T'",
    "DMF_OUT_OF_RANGE_PCT": "(ARG_T TABLE(ARG_C NUMBER)) RETURNS NUMBER AS "
                            "'SELECT ROUND(DIV0(COUNT_IF(ARG_C < 0 OR ARG_C > 100), COUNT(*)) * 100, 2) FROM ARG_T'",
    "DMF_ORPHAN_VENDOR_COUNT": "(ARG_T TABLE(ARG_C VARCHAR), ARG_REF TABLE(ARG_REF_C VARCHAR)) RETURNS NUMBER AS "
                               "'SELECT COUNT(*) FROM ARG_T WHERE ARG_C NOT IN (SELECT ARG_REF_C FROM ARG_REF)'",
}


def main(session, env):
    env = (env or "").upper()
    if env not in ("UAT", "PROD"):
        return {"status": "ERROR", "message": "ENV must be UAT or PROD"}
    tgt = f"{SRC}_{env}"
    stats, errors = {}, []
    skip_list = ",".join("'" + s + "'" for s in SKIP_SCHEMAS)

    def rw(text):
        text = re.sub(r'(?<![A-Za-z0-9_$])("?)' + SRC + r'\1(?=\.)', lambda m: f"{m.group(1)}{tgt}{m.group(1)}", text)
        return text.replace(f"'{SRC}'", f"'{tgt}'")

    def rows(sql):
        return session.sql(sql).collect()

    def ex(sql):
        session.sql(sql).collect()

    def bump(k):
        stats[k] = stats.get(k, 0) + 1

    def use(schema):
        ex(f"USE SCHEMA {tgt}.{schema}")

    def ddl(kind, fqn):
        return rows(f"SELECT GET_DDL('{kind}', '{fqn}', TRUE)")[0][0]

    def exists(schema, name, show):
        return len(rows(f"SHOW {show} LIKE '{name}' IN SCHEMA {tgt}.{schema}")) > 0

    def deploy_with_retry(items, label):
        pending = list(items)
        for _ in range(6):
            failed = []
            for schema, fqn, kind in pending:
                try:
                    use(schema)
                    ex(rw(ddl(kind, fqn)))
                    bump(label)
                except Exception as e:  # noqa: BLE001
                    failed.append((schema, fqn, kind, str(e)[:200]))
            if not failed or len(failed) == len(pending):
                for f in failed:
                    errors.append(f"{label} {f[1]}: {f[3]}")
                return
            pending = [(s, f, k) for s, f, k, _ in failed]

    # 1. database + schemas
    ex(f"CREATE DATABASE IF NOT EXISTS {tgt}")
    schemas = [r["name"] for r in rows(f"SHOW SCHEMAS IN DATABASE {SRC}") if r["name"] not in SKIP_SCHEMAS]
    for s in schemas:
        ex(f"CREATE SCHEMA IF NOT EXISTS {tgt}.{s}")
    stats["schemas"] = len(schemas)

    # 2. suspend existing target tasks so they can be replaced
    for r in rows(f"SHOW TASKS IN DATABASE {tgt}"):
        try:
            ex(f"ALTER TASK {tgt}.{r['schema_name']}.{r['name']} SUSPEND")
        except Exception:  # noqa: BLE001
            pass

    # 3. governance: tags, masking + row access policies
    for r in rows(f"SHOW TAGS IN DATABASE {SRC}"):
        try:
            vals = json.loads(r["allowed_values"]) if r["allowed_values"] else []
            allowed = (" ALLOWED_VALUES " + ", ".join("'" + v + "'" for v in vals)) if vals else ""
            ex(f"CREATE TAG IF NOT EXISTS {tgt}.{r['schema_name']}.{r['name']}{allowed}")
            bump("tags")
        except Exception as e:  # noqa: BLE001
            errors.append(f"tag {r['name']}: {str(e)[:150]}")
    for show in ("MASKING POLICIES", "ROW ACCESS POLICIES"):
        for r in rows(f"SHOW {show} IN DATABASE {SRC}"):
            try:
                if not exists(r["schema_name"], r["name"], show):
                    use(r["schema_name"])
                    ex(rw(ddl("POLICY", f"{SRC}.{r['schema_name']}.{r['name']}")))
                bump("policies")
            except Exception as e:  # noqa: BLE001
                errors.append(f"policy {r['name']}: {str(e)[:150]}")

    # 4. data metric functions
    for r in rows(f"SHOW DATA METRIC FUNCTIONS IN DATABASE {SRC}"):
        if r["catalog_name"] != SRC:
            continue
        try:
            if r["name"] not in DMF_DDL:
                errors.append(f"dmf {r['name']}: no explicit definition registered")
                continue
            if not exists(r["schema_name"], r["name"], "DATA METRIC FUNCTIONS"):
                ex(f"CREATE DATA METRIC FUNCTION {tgt}.{r['schema_name']}.{r['name']}{DMF_DDL[r['name']]}")
            bump("dmfs")
        except Exception as e:  # noqa: BLE001
            errors.append(f"dmf {r['name']}: {str(e)[:150]}")

    # 5. base tables (structure + data)
    dyn = {(r["schema_name"], r["name"]) for r in rows(f"SHOW DYNAMIC TABLES IN DATABASE {SRC}")}
    tables = rows(f"SELECT table_schema, table_name FROM {SRC}.INFORMATION_SCHEMA.TABLES "
                  f"WHERE table_type = 'BASE TABLE' AND table_schema NOT IN ({skip_list})")
    for r in tables:
        key = (r[0], r[1])
        if key in dyn or key in SKIP_TABLES:
            continue
        try:
            if key in KEEP_IF_EXISTS and exists(r[0], r[1], "TABLES"):
                bump("tables_kept")
                continue
            use(r[0])
            ex(rw(ddl("TABLE", f"{SRC}.{r[0]}.{r[1]}")))
            ex(f"INSERT INTO {tgt}.{r[0]}.{r[1]} SELECT * FROM {SRC}.{r[0]}.{r[1]}")
            bump("tables")
        except Exception as e:  # noqa: BLE001
            errors.append(f"table {r[0]}.{r[1]}: {str(e)[:150]}")

    # 6. dynamic tables + views (dependency-ordered retry)
    deploy_with_retry([(s, f"{SRC}.{s}.{n}", "TABLE") for s, n in sorted(dyn) if s not in SKIP_SCHEMAS], "dynamic_tables")
    views = rows(f"SELECT table_schema, table_name FROM {SRC}.INFORMATION_SCHEMA.VIEWS WHERE table_schema NOT IN ({skip_list})")
    deploy_with_retry([(r[0], f"{SRC}.{r[0]}.{r[1]}", "VIEW") for r in views], "views")

    # 7. procedures
    for r in rows(f"SHOW USER PROCEDURES IN DATABASE {SRC}"):
        if r["name"] in SKIP_PROCS or r["schema_name"] in SKIP_SCHEMAS:
            continue
        try:
            sig = r["arguments"].split(" RETURN ")[0]
            use(r["schema_name"])
            ex(rw(ddl("PROCEDURE", f"{SRC}.{r['schema_name']}.{sig}")))
            bump("procedures")
        except Exception as e:  # noqa: BLE001
            errors.append(f"procedure {r['name']}: {str(e)[:150]}")

    # 8. streams, search services, semantic views
    for show, kind, label in (("STREAMS", "STREAM", "streams"),
                              ("CORTEX SEARCH SERVICES", "CORTEX_SEARCH_SERVICE", "search_services"),
                              ("SEMANTIC VIEWS", "SEMANTIC_VIEW", "semantic_views")):
        for r in rows(f"SHOW {show} IN DATABASE {SRC}"):
            schema = r["schema_name"]
            if schema in SKIP_SCHEMAS and show != "STREAMS":
                continue
            try:
                ex(f"CREATE SCHEMA IF NOT EXISTS {tgt}.{schema}")
                use(schema)
                ex(rw(ddl(kind, f"{SRC}.{schema}.{r['name']}")))
                bump(label)
            except Exception as e:  # noqa: BLE001
                errors.append(f"{label} {r['name']}: {str(e)[:150]}")

    # 9. tasks + alerts (created suspended)
    deploy_with_retry([(r["schema_name"], f"{SRC}.{r['schema_name']}.{r['name']}", "TASK")
                       for r in rows(f"SHOW TASKS IN DATABASE {SRC}") if r["name"] not in SKIP_TASKS], "tasks")
    deploy_with_retry([(r["schema_name"], f"{SRC}.{r['schema_name']}.{r['name']}", "ALERT")
                       for r in rows(f"SHOW ALERTS IN DATABASE {SRC}")], "alerts")

    # 10. agents
    for r in rows(f"SHOW AGENTS IN DATABASE {SRC}"):
        try:
            spec = rows(f"DESCRIBE AGENT {SRC}.{r['schema_name']}.{r['name']}")[0]["agent_spec"]
            ex(f"CREATE OR REPLACE AGENT {tgt}.{r['schema_name']}.{r['name']} FROM SPECIFICATION {DOLLARS}{rw(spec)}{DOLLARS}")
            bump("agents")
        except Exception as e:  # noqa: BLE001
            errors.append(f"agent {r['name']}: {str(e)[:150]}")

    # 11. ML models trained on the target's own data
    for model, kind, view, extra in (
        ("Z21_OTD_FORECAST", "FORECAST", "VW_OTD_SIMPLE_SERIES", "TIMESTAMP_COLNAME => 'DS', TARGET_COLNAME => 'OTD_PCT'"),
        ("Z21_INVENTORY_ANOMALY", "ANOMALY_DETECTION", "VW_INVENTORY_ANOMALY_INPUT",
         "TIMESTAMP_COLNAME => 'DS', TARGET_COLNAME => 'INVENTORY_VALUE', SERIES_COLNAME => 'SERIES', LABEL_COLNAME => ''")):
        try:
            ex(f"CREATE OR REPLACE SNOWFLAKE.ML.{kind} {tgt}.L7_INTELLIGENCE.{model}("
               f"INPUT_DATA => SYSTEM$REFERENCE('VIEW', '{tgt}.L7_INTELLIGENCE.{view}'), {extra})")
            bump("ml_models")
        except Exception as e:  # noqa: BLE001
            errors.append(f"ml {model}: {str(e)[:150]}")

    # 12. governance attachments on raw tables: masking, row access, tags, DMFs
    for (tname,) in rows(f"SELECT table_name FROM {SRC}.INFORMATION_SCHEMA.TABLES "
                         f"WHERE table_schema = 'L1_INGESTION' AND table_type = 'BASE TABLE'"):
        s_fqn, t_fqn = f"{SRC}.L1_INGESTION.{tname}", f"{tgt}.L1_INGESTION.{tname}"
        existing = {x["POLICY_NAME"] for x in rows(
            f"SELECT * FROM TABLE({tgt}.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => '{t_fqn}', REF_ENTITY_DOMAIN => 'table'))")}
        for p in rows(f"SELECT * FROM TABLE({SRC}.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => '{s_fqn}', REF_ENTITY_DOMAIN => 'table'))"):
            pol = f"{tgt}.{p['POLICY_SCHEMA']}.{p['POLICY_NAME']}"
            try:
                if p["POLICY_NAME"] in existing:
                    pass
                elif p["POLICY_KIND"] == "MASKING_POLICY":
                    ex(f"ALTER TABLE {t_fqn} MODIFY COLUMN {p['REF_COLUMN_NAME']} SET MASKING POLICY {pol} FORCE")
                else:
                    cols = ", ".join(json.loads(p["REF_ARG_COLUMN_NAMES"]))
                    ex(f"ALTER TABLE {t_fqn} ADD ROW ACCESS POLICY {pol} ON ({cols})")
                bump("policy_attachments")
            except Exception as e:  # noqa: BLE001
                errors.append(f"attach {p['POLICY_NAME']} on {tname}: {str(e)[:120]}")
        for t in rows(f"SELECT * FROM TABLE({SRC}.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('{s_fqn}', 'table'))"):
            if t["TAG_DATABASE"] != SRC:
                continue
            tag = f"{tgt}.{t['TAG_SCHEMA']}.{t['TAG_NAME']}"
            try:
                if t["LEVEL"] == "COLUMN":
                    ex(f"ALTER TABLE {t_fqn} MODIFY COLUMN {t['COLUMN_NAME']} SET TAG {tag} = '{t['TAG_VALUE']}'")
                    bump("column_tags")
                else:
                    # inherited from the table: make sure no explicit column copy exists
                    ex(f"ALTER TABLE {t_fqn} MODIFY COLUMN {t['COLUMN_NAME']} UNSET TAG {tag}")
            except Exception as e:  # noqa: BLE001
                errors.append(f"tag {t['TAG_NAME']} on {tname}.{t['COLUMN_NAME']}: {str(e)[:120]}")
        for t in rows(f"SELECT * FROM TABLE({SRC}.INFORMATION_SCHEMA.TAG_REFERENCES('{s_fqn}', 'table'))"):
            if t["TAG_DATABASE"] == SRC and t["LEVEL"] == "TABLE":
                try:
                    ex(f"ALTER TABLE {t_fqn} SET TAG {tgt}.{t['TAG_SCHEMA']}.{t['TAG_NAME']} = '{t['TAG_VALUE']}'")
                    bump("table_tags")
                except Exception as e:  # noqa: BLE001
                    errors.append(f"tag {t['TAG_NAME']} on {tname}: {str(e)[:120]}")
        dmfs = rows(f"SELECT * FROM TABLE({SRC}.INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES("
                    f"REF_ENTITY_NAME => '{s_fqn}', REF_ENTITY_DOMAIN => 'table'))")
        if dmfs:
            try:
                ex(f"ALTER TABLE {t_fqn} SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES'")
            except Exception:  # noqa: BLE001
                pass
        for d in dmfs:
            db = tgt if d["METRIC_DATABASE_NAME"] == SRC else d["METRIC_DATABASE_NAME"]
            cols = ", ".join(a["name"] for a in json.loads(d["REF_ARGUMENTS"]))
            try:
                ex(f"ALTER TABLE {t_fqn} ADD DATA METRIC FUNCTION {db}.{d['METRIC_SCHEMA_NAME']}.{d['METRIC_NAME']} ON ({cols})")
                bump("dmf_attachments")
            except Exception as e:  # noqa: BLE001
                if "already" in str(e).lower() or "exists" in str(e).lower():
                    bump("dmf_attachments")
                else:
                    errors.append(f"dmf {d['METRIC_NAME']} on {tname}: {str(e)[:120]}")

    # 13. access grants for persona roles
    for role in ("Z21_ADMIN", "Z21_PLANNER", "Z21_PROCUREMENT", "Z21_LOGISTICS"):
        try:
            ex(f"GRANT USAGE ON DATABASE {tgt} TO ROLE {role}")
            for s in ("L5_CORE", "L6_SEMANTIC", "L7_INTELLIGENCE", "L8_ACTION"):
                ex(f"GRANT USAGE ON SCHEMA {tgt}.{s} TO ROLE {role}")
            for s in ("L5_CORE", "L6_SEMANTIC"):
                ex(f"GRANT SELECT ON ALL TABLES IN SCHEMA {tgt}.{s} TO ROLE {role}")
                ex(f"GRANT SELECT ON ALL VIEWS IN SCHEMA {tgt}.{s} TO ROLE {role}")
            bump("role_grants")
        except Exception as e:  # noqa: BLE001
            errors.append(f"grants {role}: {str(e)[:120]}")

    # 14. initialise target state from its own data; start pipeline in PROD
    for call in (f"CALL {tgt}.L3_VALIDATE.SP_REFRESH_QUARANTINE()", f"CALL {tgt}.L6_SEMANTIC.SP_REFRESH_CONSISTENCY()"):
        try:
            ex(call)
        except Exception as e:  # noqa: BLE001
            errors.append(f"init {call}: {str(e)[:120]}")
    # PROD follows the whole-project switch: a release never restarts a project that was stopped.
    project_running = any(r["state"] == "started" for r in rows(f"SHOW TASKS LIKE 'TASK_DQ_REFRESH' IN SCHEMA {SRC}.L3_VALIDATE"))
    if env == "PROD" and project_running:
        try:
            ex(f"CALL {tgt}.L8_ACTION.SP_PROJECT_START()")
            stats["pipeline"] = "STARTED"
        except Exception as e:  # noqa: BLE001
            errors.append(f"start pipeline: {str(e)[:120]}")
    elif env == "PROD":
        stats["pipeline"] = "SUSPENDED (project is stopped)"
    else:
        stats["pipeline"] = "SUSPENDED (start on demand)"

    status = "SUCCESS" if not errors else "COMPLETED_WITH_ERRORS"
    note = (env + ": " + json.dumps(stats)).replace("'", "")
    ex(f"INSERT INTO {SRC}.L8_ACTION.DECISION_AUDIT (action_type, action_by, role_used, previous_status, new_status, notes) "
       f"SELECT 'DEPLOY_ENVIRONMENT', CURRENT_USER(), CURRENT_ROLE(), 'DEPLOYING', '{status}', '{note}'")
    return {"status": status, "target": tgt, "deployed": stats, "errors": errors}
$$;

-- ------------------------------------------------------------
-- SP_RELEASE: one-step gated release (gate -> data -> dbt -> deploy)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE ZERO_TO_ONE_CHAIN.L8_ACTION.SP_RELEASE(SOURCE_ENV VARCHAR, TARGET_ENV VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    promote_result VARCHAR;
    deploy_result VARIANT;
    dbt_ok BOOLEAN;
    target_lc VARCHAR;
    deploy_status VARCHAR;
BEGIN
    IF (:SOURCE_ENV = 'DEV' AND :TARGET_ENV = 'UAT') THEN
        CALL ZERO_TO_ONE_CHAIN.L8_ACTION.SP_PROMOTE_DEV_TO_UAT() INTO :promote_result;
    ELSEIF (:SOURCE_ENV = 'UAT' AND :TARGET_ENV = 'PROD') THEN
        CALL ZERO_TO_ONE_CHAIN.L8_ACTION.SP_PROMOTE_UAT_TO_PROD() INTO :promote_result;
    ELSE
        RETURN 'ERROR: allowed releases are DEV->UAT and UAT->PROD';
    END IF;

    IF (NOT STARTSWITH(:promote_result, 'SUCCESS')) THEN
        RETURN :promote_result;
    END IF;

    target_lc := LOWER(:TARGET_ENV);
    EXECUTE IMMEDIATE 'EXECUTE DBT PROJECT ZERO_TO_ONE_CHAIN.DBT_DEPLOY.ZERO_TO_ONE_CHAIN ARGS = ''build --target ' || :target_lc || '''';
    SELECT "SUCCESS" INTO :dbt_ok FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    IF (NOT :dbt_ok) THEN
        UPDATE ZERO_TO_ONE_CHAIN.L8_ACTION.ENVIRONMENT_REGISTRY SET status = 'FAILED', dbt_test_result = 'dbt build FAILED'
          WHERE promotion_id = (SELECT MAX(promotion_id) FROM ZERO_TO_ONE_CHAIN.L8_ACTION.ENVIRONMENT_REGISTRY);
        RETURN 'FAILED: dbt build failed in ' || :TARGET_ENV || '. Release stopped before deploying upper layers.';
    END IF;

    CALL ZERO_TO_ONE_CHAIN.L8_ACTION.SP_DEPLOY_ENVIRONMENT(:TARGET_ENV) INTO :deploy_result;
    deploy_status := :deploy_result:status::VARCHAR;

    UPDATE ZERO_TO_ONE_CHAIN.L8_ACTION.ENVIRONMENT_REGISTRY
      SET dbt_test_result = 'dbt build PASSED',
          status = IFF(:deploy_status = 'SUCCESS', 'SUCCESS', 'PARTIAL'),
          notes = 'Full-stack release: data, dbt, all layers, agents. Deploy status: ' || :deploy_status
      WHERE promotion_id = (SELECT MAX(promotion_id) FROM ZERO_TO_ONE_CHAIN.L8_ACTION.ENVIRONMENT_REGISTRY);

    IF (:deploy_status = 'SUCCESS') THEN
        RETURN 'SUCCESS: ' || :SOURCE_ENV || ' released to ' || :TARGET_ENV || ' (DQ gate passed, dbt build passed, full stack deployed)';
    END IF;
    RETURN 'PARTIAL: deployed with errors: ' || ARRAY_TO_STRING(:deploy_result:errors::ARRAY, '; ');
END;
$$;


-- =====================================================================
-- Per-environment pipeline start/stop (deployed to every environment).
-- Generic: START resumes the whole task graph from its root; STOP suspends whatever tasks
-- exist, so DEV (which also has TASK_RELEASE_TRAIN) and UAT/PROD share one definition.
-- =====================================================================
CREATE OR REPLACE PROCEDURE ZERO_TO_ONE_CHAIN.L8_ACTION.SP_PROJECT_START()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='Resume the pipeline task graph (all dependents, then root) and all alerts in this environment'
EXECUTE AS CALLER
AS '
DECLARE
    alerts RESULTSET;
    n_alerts INTEGER DEFAULT 0;
    n_tasks INTEGER;
BEGIN
    -- Resumes every dependent of the root (children first) and then the root itself.
    SELECT SYSTEM$TASK_DEPENDENTS_ENABLE(''ZERO_TO_ONE_CHAIN.L3_VALIDATE.TASK_DQ_REFRESH'');
    SELECT COUNT(*) INTO :n_tasks FROM TABLE(ZERO_TO_ONE_CHAIN.INFORMATION_SCHEMA.TASK_DEPENDENTS(
        TASK_NAME => ''ZERO_TO_ONE_CHAIN.L3_VALIDATE.TASK_DQ_REFRESH'', RECURSIVE => TRUE));

    SHOW ALERTS IN SCHEMA ZERO_TO_ONE_CHAIN.L8_ACTION;
    alerts := (SELECT "name" AS name FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    FOR a IN alerts DO
        EXECUTE IMMEDIATE ''ALTER ALERT ZERO_TO_ONE_CHAIN.L8_ACTION."'' || a.name || ''" RESUME'';
        n_alerts := n_alerts + 1;
    END FOR;

    INSERT INTO ZERO_TO_ONE_CHAIN.L8_ACTION.DECISION_AUDIT
        (recommendation_id, action_type, action_by, role_used, previous_status, new_status, notes)
    VALUES (NULL, ''PROJECT_START'', CURRENT_USER(), CURRENT_ROLE(), ''STOPPED'', ''RUNNING'',
            :n_tasks || '' tasks + '' || :n_alerts || '' alerts resumed at '' || CURRENT_TIMESTAMP()::VARCHAR);
    RETURN ''PROJECT STARTED: '' || :n_tasks || '' tasks resumed, '' || :n_alerts || '' alerts resumed'';
END;
';

CREATE OR REPLACE PROCEDURE ZERO_TO_ONE_CHAIN.L8_ACTION.SP_PROJECT_STOP()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='Suspend the pipeline task graph (root first, then every task) and all alerts in this environment'
EXECUTE AS CALLER
AS '
DECLARE
    tasks RESULTSET;
    alerts RESULTSET;
    n_tasks INTEGER DEFAULT 0;
    n_alerts INTEGER DEFAULT 0;
BEGIN
    -- Root first so no new graph run can start while the children are being suspended.
    ALTER TASK IF EXISTS ZERO_TO_ONE_CHAIN.L3_VALIDATE.TASK_DQ_REFRESH SUSPEND;
    SHOW TASKS IN SCHEMA ZERO_TO_ONE_CHAIN.L3_VALIDATE;
    tasks := (SELECT "name" AS name FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    FOR t IN tasks DO
        EXECUTE IMMEDIATE ''ALTER TASK ZERO_TO_ONE_CHAIN.L3_VALIDATE."'' || t.name || ''" SUSPEND'';
        n_tasks := n_tasks + 1;
    END FOR;

    SHOW ALERTS IN SCHEMA ZERO_TO_ONE_CHAIN.L8_ACTION;
    alerts := (SELECT "name" AS name FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    FOR a IN alerts DO
        EXECUTE IMMEDIATE ''ALTER ALERT ZERO_TO_ONE_CHAIN.L8_ACTION."'' || a.name || ''" SUSPEND'';
        n_alerts := n_alerts + 1;
    END FOR;

    INSERT INTO ZERO_TO_ONE_CHAIN.L8_ACTION.DECISION_AUDIT
        (recommendation_id, action_type, action_by, role_used, previous_status, new_status, notes)
    VALUES (NULL, ''PROJECT_STOP'', CURRENT_USER(), CURRENT_ROLE(), ''RUNNING'', ''STOPPED'',
            :n_tasks || '' tasks + '' || :n_alerts || '' alerts suspended at '' || CURRENT_TIMESTAMP()::VARCHAR);
    RETURN ''PROJECT STOPPED: '' || :n_tasks || '' tasks suspended, '' || :n_alerts || '' alerts suspended'';
END;
';


-- =====================================================================
-- Whole-project switch (Command center / sidebar / Operations buttons)
--   STOP  : suspends tasks + alerts in PROD, UAT and DEV
--   START : resumes DEV and PROD (UAT runs only during releases)
-- Each environment keeps its own SP_PROJECT_START / SP_PROJECT_STOP; this
-- control-plane procedure lives in DEV only (excluded from deploys).
-- =====================================================================
CREATE OR REPLACE PROCEDURE ZERO_TO_ONE_CHAIN.L8_ACTION.SP_PROJECT_CONTROL(ACTION VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Whole-project switch. STOP suspends tasks + alerts in DEV, UAT and PROD. START resumes DEV and PROD (UAT runs only during releases).'
EXECUTE AS CALLER
AS
$$
DECLARE
    act VARCHAR DEFAULT UPPER(TRIM(:ACTION));
    envs ARRAY;
    db VARCHAR;
    env VARCHAR;
    summary VARCHAR DEFAULT '';
    failures INTEGER DEFAULT 0;
BEGIN
    IF (act NOT IN ('START', 'STOP')) THEN
        RETURN 'FAILED: action must be START or STOP';
    END IF;
    envs := IFF(act = 'STOP',
                ARRAY_CONSTRUCT('ZERO_TO_ONE_CHAIN_PROD', 'ZERO_TO_ONE_CHAIN_UAT', 'ZERO_TO_ONE_CHAIN'),
                ARRAY_CONSTRUCT('ZERO_TO_ONE_CHAIN', 'ZERO_TO_ONE_CHAIN_PROD'));
    FOR i IN 0 TO ARRAY_SIZE(envs) - 1 DO
        db := envs[i]::VARCHAR;
        env := IFF(db = 'ZERO_TO_ONE_CHAIN', 'DEV', REPLACE(db, 'ZERO_TO_ONE_CHAIN_', ''));
        BEGIN
            EXECUTE IMMEDIATE 'CALL ' || db || '.L8_ACTION.SP_PROJECT_' || act || '()';
            summary := summary || env || ' ok; ';
        EXCEPTION
            WHEN OTHER THEN
                failures := failures + 1;
                summary := summary || env || ' failed (' || SQLERRM || '); ';
        END;
    END FOR;
    RETURN IFF(failures = 0, 'SUCCESS', 'PARTIAL') || ': project ' || IFF(act = 'STOP', 'stopped', 'started') || ' - ' || RTRIM(summary, '; ');
END;
$$;
