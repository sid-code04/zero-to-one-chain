-- =====================================================================
-- Release train: DEV change -> automatic UAT release + verification -> human-approved PROD
--   SP_DEV_FINGERPRINT()       : content hash of DEV raw data + every deployable code object
--   SP_RELEASE_TRAIN(trigger)  : called by TASK_RELEASE_TRAIN (end of the DEV hourly DAG) or the
--                                Operations page; releases DEV->UAT only when DEV raw data or code changed
--   SP_DECIDE_RELEASE(id, ...) : Action-queue approval gate that runs UAT->PROD, refused unless DEV still
--                                matches the build that passed UAT (PROD code is deployed from DEV)
--   RELEASE_TRAIN              : ledger of every check, release and decision
-- All of these live in DEV only (control plane) and are excluded from environment deploys.
-- =====================================================================

CREATE TABLE IF NOT EXISTS ZERO_TO_ONE_CHAIN.L8_ACTION.RELEASE_TRAIN (
	TRAIN_ID NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1 ORDER,
	CHECKED_AT TIMESTAMP_LTZ(9) DEFAULT CURRENT_TIMESTAMP(),
	TRIGGER_TYPE VARCHAR(16777216) COMMENT 'SCHEDULED (DEV pipeline) | MANUAL (Operations page)',
	STATUS VARCHAR(16777216) COMMENT 'SKIPPED_NO_CHANGE | BLOCKED | RELEASING_UAT | UAT_FAILED | AWAITING_APPROVAL | RELEASING_PROD | PROD_RELEASED | PROD_FAILED | REJECTED | SUPERSEDED',
	CHANGE_SUMMARY VARCHAR(16777216),
	SNAPSHOT VARIANT COMMENT 'Fingerprint of DEV raw data + code at check time',
	UAT_RESULT VARCHAR(16777216),
	UAT_RELEASED_AT TIMESTAMP_LTZ(9),
	UAT_CHECKS VARIANT COMMENT 'Parity, DQ and consistency checks run against UAT',
	RECOMMENDATION_ID NUMBER(38,0) COMMENT 'Approval card in L8_ACTION.RECOMMENDATIONS',
	DECIDED_BY VARCHAR(16777216),
	DECIDED_AT TIMESTAMP_LTZ(9),
	DECISION_NOTE VARCHAR(16777216),
	PROD_RESULT VARCHAR(16777216),
	PROD_RELEASED_AT TIMESTAMP_LTZ(9)
)COMMENT='Release train: DEV change detection -> automatic UAT release -> human-approved PROD release'
;

CREATE OR REPLACE PROCEDURE ZERO_TO_ONE_CHAIN.L8_ACTION.SP_DEV_FINGERPRINT()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
COMMENT = 'Content fingerprint of DEV: HASH_AGG of every raw table + hashes of every deployable code definition'
EXECUTE AS CALLER
AS
$$
import hashlib

DEV = "ZERO_TO_ONE_CHAIN"
SKIP_SCHEMAS = ("INFORMATION_SCHEMA", "PUBLIC", "DBT_DEPLOY", "DATA_GEN")
# Control-plane objects never deploy to UAT/PROD, so they are not part of a release.
CONTROL_PLANE = {"SP_DEV_FINGERPRINT", "SP_RELEASE_TRAIN", "SP_DECIDE_RELEASE", "SP_RELEASE", "SP_DEPLOY_ENVIRONMENT",
                 "SP_PROMOTE_DEV_TO_UAT", "SP_PROMOTE_UAT_TO_PROD", "SP_PROJECT_CONTROL"}
CONTROL_TASKS = {"TASK_RELEASE_TRAIN"}


def h(text):
    return hashlib.md5((text or "").encode()).hexdigest()


def main(session):
    q = lambda sql: session.sql(sql).collect()
    skip = ",".join(f"'{s}'" for s in SKIP_SCHEMAS)
    data = {}
    for r in q(f"SELECT table_name, row_count FROM {DEV}.INFORMATION_SCHEMA.TABLES "
               f"WHERE table_schema = 'L1_INGESTION' AND table_type = 'BASE TABLE' ORDER BY 1"):
        digest = q(f"SELECT HASH_AGG(*) FROM {DEV}.L1_INGESTION.{r['TABLE_NAME']}")[0][0]
        data[r["TABLE_NAME"]] = {"rows": int(r["ROW_COUNT"] or 0), "hash": str(digest)}
    code = {}
    for r in q(f"SELECT table_schema || '.' || table_name AS k, view_definition AS d "
               f"FROM {DEV}.INFORMATION_SCHEMA.VIEWS WHERE table_schema NOT IN ({skip})"):
        code[f"view:{r['K']}"] = h(r["D"])
    for r in q(f"SELECT procedure_schema || '.' || procedure_name || argument_signature AS k, procedure_name AS n, "
               f"procedure_definition AS d FROM {DEV}.INFORMATION_SCHEMA.PROCEDURES "
               f"WHERE procedure_schema NOT IN ({skip})"):
        if r["N"] not in CONTROL_PLANE:
            code[f"procedure:{r['K']}"] = h(r["D"])
    for show, kind, field in (("DYNAMIC TABLES", "dynamic_table", "text"), ("TASKS", "task", "definition")):
        for r in q(f"SHOW {show} IN DATABASE {DEV}"):
            if r["schema_name"] in SKIP_SCHEMAS or r["name"] in CONTROL_TASKS:
                continue
            extra = str(r["predecessors"]) + str(r["schedule"]) if kind == "task" else ""
            code[f"{kind}:{r['schema_name']}.{r['name']}"] = h(str(r[field]) + extra)
    for show, kind in (("SEMANTIC VIEWS", "SEMANTIC_VIEW"), ("CORTEX SEARCH SERVICES", "CORTEX_SEARCH_SERVICE")):
        for r in q(f"SHOW {show} IN DATABASE {DEV}"):
            fqn = f"{DEV}.{r['schema_name']}.{r['name']}"
            code[f"{kind.lower()}:{r['schema_name']}.{r['name']}"] = h(q(f"SELECT GET_DDL('{kind}', '{fqn}')")[0][0])
    for r in q(f"SHOW AGENTS IN DATABASE {DEV}"):
        spec = q(f"DESCRIBE AGENT {DEV}.{r['schema_name']}.{r['name']}")[0]["agent_spec"]
        code[f"agent:{r['schema_name']}.{r['name']}"] = h(spec)
    for r in q(f"SHOW DBT PROJECTS IN DATABASE {DEV}"):
        code[f"dbt_project:{r['name']}"] = h(str(r["updated_on"]) + str(r["default_version"]))
    return {"data": data, "code": code}
$$;

CREATE OR REPLACE PROCEDURE ZERO_TO_ONE_CHAIN.L8_ACTION.SP_RELEASE_TRAIN(TRIGGER_TYPE VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
COMMENT = 'Release train: if DEV changed since the last UAT release, release DEV->UAT, verify UAT, and raise a PROD approval card.'
EXECUTE AS CALLER
AS
$$
import json

DEV, UAT = "ZERO_TO_ONE_CHAIN", "ZERO_TO_ONE_CHAIN_UAT"
L8 = f"{DEV}.L8_ACTION"
# A train in one of these states means UAT was released from its snapshot.
RELEASED_STATES = ("AWAITING_APPROVAL", "RELEASING_PROD", "PROD_RELEASED", "PROD_FAILED", "REJECTED", "SUPERSEDED")
IN_FLIGHT = ("RELEASING_UAT", "RELEASING_PROD")
STALE_MINUTES = 45  # a release takes ~5 minutes; anything older crashed without recording its outcome
METRICS = ("METRICS VW_METRIC_OTD.OTD_PCT, VW_METRIC_OTD.OTIF_PCT, VW_METRIC_OTD.FILL_RATE, "
           "VW_METRIC_OTD.DELIVERED_LINES")


def diff(old, new):
    parts, changed = [], False
    old_d, new_d = (old or {}).get("data", {}), new["data"]
    for t, v in new_d.items():
        prev = old_d.get(t)
        if prev is None or prev["hash"] != v["hash"]:
            changed = True
            delta = v["rows"] - (prev["rows"] if prev else 0)
            parts.append(f"{t} ({'+' if delta >= 0 else ''}{delta:,} rows)" if delta else f"{t} (values changed)")
    old_c, new_c = (old or {}).get("code", {}), new["code"]
    kinds = {}
    for k in set(old_c) | set(new_c):
        if old_c.get(k) != new_c.get(k):
            changed = True
            kind = k.split(":")[0].replace("_", " ")
            kinds[kind] = kinds.get(kind, 0) + 1
    summary = []
    if parts:
        summary.append("Data: " + ", ".join(parts))
    if kinds:
        summary.append("Code: " + ", ".join(f"{n} {k}{'s' if n > 1 else ''}" for k, n in sorted(kinds.items())))
    return changed, "; ".join(summary) or "No changes"


def main(session, trigger_type):
    trigger = (trigger_type or "SCHEDULED").upper()
    if trigger not in ("SCHEDULED", "MANUAL"):
        return {"status": "ERROR", "message": "TRIGGER_TYPE must be SCHEDULED or MANUAL"}
    run = lambda sql, params=None: session.sql(sql, params=params).collect()

    def record(status, summary, snap):
        run(f"INSERT INTO {L8}.RELEASE_TRAIN (trigger_type, status, change_summary, snapshot) "
            f"SELECT ?, ?, ?, PARSE_JSON(?)", [trigger, status, summary, json.dumps(snap)])
        return run(f"SELECT MAX(train_id) FROM {L8}.RELEASE_TRAIN")[0][0]

    def fail(tid, message, checks=None):
        run(f"UPDATE {L8}.RELEASE_TRAIN SET status = 'UAT_FAILED', uat_result = ?, uat_checks = PARSE_JSON(?) "
            f"WHERE train_id = ?", [message[:4000], json.dumps(checks), tid])
        return {"status": "UAT_FAILED", "train_id": tid, "message": message[:500], "checks": checks}

    # Close out releases that crashed mid-flight, then refuse to overlap a live one.
    run(f"UPDATE {L8}.RELEASE_TRAIN SET status = IFF(status = 'RELEASING_UAT', 'UAT_FAILED', 'PROD_FAILED'), "
        f"uat_result = IFF(status = 'RELEASING_UAT', 'Interrupted: no outcome recorded', uat_result), "
        f"prod_result = IFF(status = 'RELEASING_PROD', 'Interrupted: no outcome recorded', prod_result) "
        f"WHERE status IN ('RELEASING_UAT', 'RELEASING_PROD') "
        f"AND COALESCE(decided_at, checked_at) < DATEADD(MINUTE, -{STALE_MINUTES}, CURRENT_TIMESTAMP())")
    busy = run(f"SELECT train_id, status FROM {L8}.RELEASE_TRAIN WHERE status IN ('RELEASING_UAT', 'RELEASING_PROD')")
    if busy:
        return {"status": "SKIPPED_BUSY", "message": f"Release #{busy[0][0]} is {busy[0][1].lower().replace('_', ' ')}"}

    snap = json.loads(session.call(f"{L8}.SP_DEV_FINGERPRINT"))
    prev = run(f"SELECT snapshot FROM {L8}.RELEASE_TRAIN WHERE status IN ({','.join('?' for _ in RELEASED_STATES)}) "
               f"ORDER BY train_id DESC LIMIT 1", list(RELEASED_STATES))
    # No previous release snapshot means the UAT state is unknown, so treat everything as changed.
    changed, summary = diff(json.loads(prev[0][0]) if prev else None, snap)
    if not prev:
        summary = "First release-train run: " + summary
    if not changed and trigger == "SCHEDULED":
        tid = record("SKIPPED_NO_CHANGE", "DEV unchanged since last UAT release", {"data": {}, "code": {}})
        return {"status": "SKIPPED_NO_CHANGE", "train_id": tid}
    if not changed:
        summary = "Manual release, no changes detected in DEV"

    critical = run(f"SELECT COUNT(*) FROM {DEV}.L3_VALIDATE.DQ_QUARANTINE "
                   f"WHERE severity = 'CRITICAL' AND resolved_at IS NULL")[0][0]
    if critical:
        tid = record("BLOCKED", f"{summary}. Blocked: {critical} critical DQ issues open in DEV", snap)
        return {"status": "BLOCKED", "train_id": tid, "critical_issues": critical}

    tid = record("RELEASING_UAT", summary, snap)
    try:
        uat_msg = str(run(f"CALL {L8}.SP_RELEASE('DEV', 'UAT')")[0][0])
    except Exception as e:  # noqa: BLE001
        return fail(tid, f"Release error: {e}")
    if not uat_msg.startswith("SUCCESS"):
        return fail(tid, uat_msg)

    # Verify UAT before asking for PROD approval.
    try:
        par = {r["ENV"]: r for r in run(
            f"SELECT 'DEV' AS env, * FROM SEMANTIC_VIEW({DEV}.L6_SEMANTIC.SUPPLY_CHAIN_ANALYTICS {METRICS}) UNION ALL "
            f"SELECT 'UAT', * FROM SEMANTIC_VIEW({UAT}.L6_SEMANTIC.SUPPLY_CHAIN_ANALYTICS {METRICS})")}
        metric_names = ("OTD_PCT", "OTIF_PCT", "FILL_RATE", "DELIVERED_LINES")
        parity = all(round(float(par["DEV"][m]), 4) == round(float(par["UAT"][m]), 4) for m in metric_names)
        uat_critical = run(f"SELECT COUNT(*) FROM {UAT}.L3_VALIDATE.DQ_QUARANTINE "
                           f"WHERE severity = 'CRITICAL' AND resolved_at IS NULL")[0][0]
        mismatched = run(f"SELECT COUNT_IF(NOT all_match) FROM {UAT}.L6_SEMANTIC.CONSISTENCY_PROOF")[0][0]
    except Exception as e:  # noqa: BLE001
        return fail(tid, f"UAT verification error: {e}")
    checks = {
        "dbt_build_and_tests": "PASSED",
        "metric_parity_dev_uat": "PASSED" if parity else "FAILED",
        "uat_critical_dq_issues": int(uat_critical),
        "uat_consistency_mismatches": int(mismatched),
        "uat_metrics": {m: float(par["UAT"][m]) for m in metric_names},
    }
    if not (parity and not uat_critical and not mismatched):
        return fail(tid, "UAT verification failed", checks)

    # Only the newest verified UAT build can be promoted.
    for (old_tid, old_rec) in run(f"SELECT train_id, recommendation_id FROM {L8}.RELEASE_TRAIN "
                                  f"WHERE status = 'AWAITING_APPROVAL'"):
        run(f"UPDATE {L8}.RELEASE_TRAIN SET status = 'SUPERSEDED', decision_note = ? WHERE train_id = ?",
            [f"Superseded by release #{tid}", old_tid])
        if old_rec:
            run(f"UPDATE {L8}.RECOMMENDATIONS SET status = 'SUPERSEDED', rejected_reason = ? "
                f"WHERE recommendation_id = ? AND status = 'PENDING'", [f"Superseded by release #{tid}", old_rec])

    m = checks["uat_metrics"]
    title = f"Approve release #{tid} to PROD"
    description = (f"{summary}. UAT passed every gate: dbt build and tests, DEV/UAT metric parity "
                   f"(OTD {m['OTD_PCT']:.2f}%, OTIF {m['OTIF_PCT']:.2f}%, fill {m['FILL_RATE']:.2f}%, "
                   f"{int(m['DELIVERED_LINES']):,} lines), 0 critical DQ issues, consistency proof matched.")
    run(f"INSERT INTO {L8}.RECOMMENDATIONS (category, severity, title, description, affected_entity_type, "
        f"affected_entity_id, recommended_action, supporting_evidence, status) "
        f"SELECT 'RELEASE', 'HIGH', ?, ?, 'ENVIRONMENT', 'PROD', ?, PARSE_JSON(?), 'PENDING'",
        [title, description, "Approve to release UAT to PROD: data, dbt models, all layers, semantic view, agents",
         json.dumps({"train_id": tid, "checks": checks})])
    rec_id = run(f"SELECT MAX(recommendation_id) FROM {L8}.RECOMMENDATIONS WHERE title = ?", [title])[0][0]
    run(f"UPDATE {L8}.RELEASE_TRAIN SET status = 'AWAITING_APPROVAL', uat_result = ?, "
        f"uat_released_at = CURRENT_TIMESTAMP(), uat_checks = PARSE_JSON(?), recommendation_id = ? WHERE train_id = ?",
        [uat_msg, json.dumps(checks), rec_id, tid])
    return {"status": "AWAITING_APPROVAL", "train_id": tid, "recommendation_id": rec_id, "changes": summary}
$$;

CREATE OR REPLACE PROCEDURE ZERO_TO_ONE_CHAIN.L8_ACTION.SP_DECIDE_RELEASE(RECOMMENDATION_ID NUMBER, DECISION VARCHAR, NOTE VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
COMMENT = 'Human approval gate for PROD: approve runs UAT->PROD only if DEV still matches the verified UAT build; reject closes the train. Fully audited.'
EXECUTE AS CALLER
AS
$$
import json

L8 = "ZERO_TO_ONE_CHAIN.L8_ACTION"


def main(session, rec_id, decision, note):
    run = lambda sql, params=None: session.sql(sql, params=params).collect()
    decision = (decision or "").upper()
    if decision not in ("APPROVE", "REJECT"):
        return "FAILED: decision must be APPROVE or REJECT"
    rec = run(f"SELECT category, status FROM {L8}.RECOMMENDATIONS WHERE recommendation_id = ?", [rec_id])
    if not rec or rec[0]["CATEGORY"] != "RELEASE":
        return "FAILED: not a release approval"
    if rec[0]["STATUS"] != "PENDING":
        return f"FAILED: this release is already {rec[0]['STATUS'].lower()}"
    train = run(f"SELECT train_id, status, snapshot FROM {L8}.RELEASE_TRAIN WHERE recommendation_id = ?", [rec_id])
    if not train or train[0]["STATUS"] != "AWAITING_APPROVAL":
        return "FAILED: release train is not awaiting approval"
    tid = train[0]["TRAIN_ID"]
    busy = run(f"SELECT train_id FROM {L8}.RELEASE_TRAIN WHERE status IN ('RELEASING_UAT', 'RELEASING_PROD')")
    if busy:
        return f"FAILED: release #{busy[0][0]} is in progress; try again when it finishes"

    note = (note or "").strip()[:500] or f"{decision.title()}d in Action queue"
    who = run("SELECT CURRENT_USER(), CURRENT_ROLE()")[0]

    def audit(new_status, text):
        run(f"INSERT INTO {L8}.DECISION_AUDIT (recommendation_id, action_type, action_by, role_used, previous_status, "
            f"new_status, notes) SELECT ?, 'RELEASE_DECISION', ?, ?, 'PENDING', ?, ?",
            [rec_id, who[0], who[1], new_status, f"Release #{tid}: {text}"])

    if decision == "APPROVE":
        # PROD code is deployed from DEV, so DEV must still be exactly the build that passed UAT.
        verified = json.loads(train[0]["SNAPSHOT"])
        current = json.loads(session.call(f"{L8}.SP_DEV_FINGERPRINT"))
        if verified != current:
            return (f"REFUSED: DEV changed after release #{tid} was verified in UAT. The release train will "
                    f"verify the new build in UAT first; approve that release instead.")

    rec_status = "APPROVED" if decision == "APPROVE" else "REJECTED"
    run(f"UPDATE {L8}.RECOMMENDATIONS SET status = ?, approved_by = CURRENT_USER(), approved_at = CURRENT_TIMESTAMP(), "
        f"rejected_reason = IFF(? = 'REJECTED', ?, NULL) WHERE recommendation_id = ?", [rec_status, rec_status, note, rec_id])
    run(f"UPDATE {L8}.RELEASE_TRAIN SET status = ?, decided_by = CURRENT_USER(), decided_at = CURRENT_TIMESTAMP(), "
        f"decision_note = ? WHERE train_id = ?", ["RELEASING_PROD" if decision == "APPROVE" else "REJECTED", note, tid])
    audit(rec_status, note)
    if decision == "REJECT":
        return f"REJECTED: release #{tid} will not go to PROD"

    try:
        msg = str(run(f"CALL {L8}.SP_RELEASE('UAT', 'PROD')")[0][0])
    except Exception as e:  # noqa: BLE001
        msg = f"Release error: {e}"
    ok = msg.startswith("SUCCESS")
    run(f"UPDATE {L8}.RELEASE_TRAIN SET status = ?, prod_result = ?, "
        f"prod_released_at = IFF(?, CURRENT_TIMESTAMP(), NULL) WHERE train_id = ?",
        ["PROD_RELEASED" if ok else "PROD_FAILED", msg[:4000], ok, tid])
    run(f"UPDATE {L8}.RECOMMENDATIONS SET implemented_at = IFF(?, CURRENT_TIMESTAMP(), NULL) WHERE recommendation_id = ?",
        [ok, rec_id])
    return f"{'SUCCESS' if ok else 'FAILED'}: release #{tid} to PROD - {msg[:500]}"
$$;

-- Final task of the DEV hourly pipeline. The root (TASK_DQ_REFRESH) must be suspended to add it.
CREATE TASK IF NOT EXISTS ZERO_TO_ONE_CHAIN.L3_VALIDATE.TASK_RELEASE_TRAIN
    WAREHOUSE = Z21_WH
    USER_TASK_TIMEOUT_MS = 1800000
    COMMENT = 'Release train: after a successful DEV pipeline run, release DEV->UAT only if DEV raw data or code changed; raises a PROD approval card'
    AFTER ZERO_TO_ONE_CHAIN.L3_VALIDATE.TASK_PIPELINE_LOG
AS
    CALL ZERO_TO_ONE_CHAIN.L8_ACTION.SP_RELEASE_TRAIN('SCHEDULED');
