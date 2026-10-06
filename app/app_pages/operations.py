import json

import pandas as pd
import streamlit as st

import ui
from ui import DB

ui.header("Operations", "Pipeline control and governed release train: DEV → UAT automatically, PROD on approval")

ENVS = {"DEV": DB, "UAT": f"{DB}_UAT", "PROD": f"{DB}_PROD"}
METRICS = "METRICS VW_METRIC_OTD.OTD_PCT, VW_METRIC_OTD.OTIF_PCT, VW_METRIC_OTD.FILL_RATE, VW_METRIC_OTD.DELIVERED_LINES"


@st.dialog("Run release train", width="medium")
def run_train():
    st.markdown("Release **DEV → UAT** now instead of waiting for the hourly pipeline:")
    st.markdown("1. Data quality gate (refused on any critical issue)\n2. Data promotion\n"
                "3. dbt build and tests against UAT\n4. Full-stack deploy: layers, policies, tasks, "
                "semantic view, search, agents\n5. UAT verification: metric parity with DEV, data quality, "
                "consistency proof\n6. A **PROD approval** card is raised in the Action queue")
    if st.button("Run release train", type="primary", icon=":material/train:", width="stretch"):
        with st.status("Releasing DEV → UAT (about 5 minutes)", expanded=True) as status:
            st.write("Gate, promotion, dbt build and tests, deploy, verification")
            res = ui.run(f"CALL {DB}.L8_ACTION.SP_RELEASE_TRAIN('MANUAL')")[0][0]
            res = json.loads(res) if isinstance(res, str) else res
            ok = res.get("status") == "AWAITING_APPROVAL"
            st.write({"AWAITING_APPROVAL": f"Release #{res.get('train_id')} verified in UAT and waiting for PROD "
                                           f"approval. Changes: {res.get('changes')}",
                      "BLOCKED": f"Blocked: {res.get('critical_issues')} critical data quality issues in DEV",
                      "SKIPPED_BUSY": res.get("message", "Another release is in progress")}.get(
                          res.get("status"), res.get("message") or str(res)))
            status.update(label="UAT verified, awaiting PROD approval" if ok else "Release did not complete",
                          state="complete" if ok else "error")
        ui.clear_cache()


def when(ts) -> str:
    return f"{ts:%d %b %H:%M}" if pd.notna(ts) else ""


def train_tracker():
    trains = ui.q_live(f"""
        SELECT train_id, checked_at, trigger_type, status, change_summary, uat_released_at, decided_by, decided_at,
               decision_note, prod_released_at, recommendation_id, uat_checks:metric_parity_dev_uat::VARCHAR AS parity
        FROM {DB}.L8_ACTION.RELEASE_TRAIN ORDER BY train_id DESC LIMIT 50
    """)
    releases = trains[trains.STATUS != "SKIPPED_NO_CHANGE"]
    last_check = trains.CHECKED_AT.max() if len(trains) else None
    with ui.card("Release train",
                 "Runs at the end of every DEV pipeline · releases to UAT only when DEV data or code changed · "
                 "PROD needs a human approval"):
        if releases.empty:
            st.caption("No releases yet.")
            return
        t = releases.iloc[0]
        st.markdown(f"**Release #{int(t.TRAIN_ID)}** &nbsp; {ui.TRAIN_STATUS.get(t.STATUS, t.STATUS)}")
        st.caption(str(t.CHANGE_SUMMARY)[:300])
        uat_ok = t.STATUS in ("AWAITING_APPROVAL", "RELEASING_PROD", "PROD_RELEASED", "PROD_FAILED", "REJECTED",
                              "SUPERSEDED")
        steps = [
            ("DEV change detected", True, f"{when(t.CHECKED_AT)} · {str(t.TRIGGER_TYPE).lower()}"),
            ("UAT released and verified", uat_ok,
             f"{when(t.UAT_RELEASED_AT)} · parity {str(t.PARITY).lower()}" if uat_ok and pd.notna(t.UAT_RELEASED_AT)
             else {"RELEASING_UAT": "in progress", "UAT_FAILED": "failed", "BLOCKED": "blocked by data quality"}.get(t.STATUS, "")),
            ("Human approval", t.STATUS in ("RELEASING_PROD", "PROD_RELEASED", "PROD_FAILED"),
             f"{t.DECIDED_BY} · {when(t.DECIDED_AT)}" if pd.notna(t.DECIDED_BY) else
             {"AWAITING_APPROVAL": "waiting in Action queue", "REJECTED": "rejected",
              "SUPERSEDED": "superseded"}.get(t.STATUS, "")),
            ("In PROD", t.STATUS == "PROD_RELEASED",
             when(t.PROD_RELEASED_AT) if pd.notna(t.PROD_RELEASED_AT) else
             {"RELEASING_PROD": "in progress", "PROD_FAILED": "failed"}.get(t.STATUS, "")),
        ]
        with st.container(horizontal=True):
            for name, done, detail in steps:
                icon = ":material/check_circle:" if done else ":material/radio_button_unchecked:"
                with st.container(border=True):
                    st.markdown(f"{icon} **{name}**")
                    st.caption(detail or "—")
        if pd.notna(last_check):
            st.caption(f"Last check {when(last_check)} · {len(trains) - len(releases)} hourly checks found "
                       f"no change and skipped the release")
        st.dataframe(releases, hide_index=True, width="stretch",
                     column_order=["TRAIN_ID", "STATUS", "CHANGE_SUMMARY", "UAT_RELEASED_AT", "DECIDED_BY",
                                   "DECISION_NOTE", "PROD_RELEASED_AT"],
                     column_config={
                         "TRAIN_ID": st.column_config.NumberColumn("Release", format="#%d", width="small"),
                         "STATUS": st.column_config.TextColumn("Status"),
                         "CHANGE_SUMMARY": st.column_config.TextColumn("What changed", width="large"),
                         "UAT_RELEASED_AT": st.column_config.DatetimeColumn("In UAT", format="DD MMM HH:mm"),
                         "DECIDED_BY": st.column_config.TextColumn("Decided by"),
                         "DECISION_NOTE": st.column_config.TextColumn("Note"),
                         "PROD_RELEASED_AT": st.column_config.DatetimeColumn("In PROD", format="DD MMM HH:mm"),
                     })


def render():
    parity = ui.q(" UNION ALL ".join(
        f"SELECT '{env}' AS env, * FROM SEMANTIC_VIEW({db}.L6_SEMANTIC.SUPPLY_CHAIN_ANALYTICS {METRICS})"
        for env, db in ENVS.items())).set_index("ENV")
    last = ui.q(f"""
        SELECT target_env, status, promoted_at, dbt_test_result
        FROM {DB}.L8_ACTION.ENVIRONMENT_REGISTRY
        QUALIFY ROW_NUMBER() OVER (PARTITION BY target_env ORDER BY promoted_at DESC) = 1
    """).set_index("TARGET_ENV")
    tasks = ui.q_live(f"""
        SELECT name, state FROM TABLE({DB}.INFORMATION_SCHEMA.TASK_DEPENDENTS(
            TASK_NAME => '{DB}.L3_VALIDATE.TASK_DQ_REFRESH', RECURSIVE => TRUE))
    """)
    running = int((tasks.STATE == "started").sum())
    pending = ui.q_live(f"""
        SELECT recommendation_id, title, description FROM {DB}.L8_ACTION.RECOMMENDATIONS
        WHERE category = 'RELEASE' AND status = 'PENDING' ORDER BY recommendation_id DESC LIMIT 1
    """)

    in_sync = parity.OTD_PCT.round(4).nunique() == 1 and parity.DELIVERED_LINES.nunique() == 1
    ui.finding("**All three environments return identical canonical metrics** from their own data, "
               "so what was tested in UAT is exactly what PROD serves." if in_sync else
               "**Environments are out of sync.** Release DEV → UAT → PROD to align them.",
               kind="ok" if in_sync else "risk")

    cols = st.columns([4, 1, 4, 1, 4], vertical_alignment="center")
    for i, env in enumerate(ENVS):
        with cols[i * 2].container(border=True):
            badge = {"DEV": ":blue-badge[Development]", "UAT": ":orange-badge[Acceptance]",
                     "PROD": ":green-badge[Production]"}[env]
            st.markdown(f"### {env}\n{badge}")
            r = parity.loc[env]
            ui.kpi("On-time delivery", f"{r.OTD_PCT:.2f}%")
            st.caption(f"OTIF {r.OTIF_PCT:.2f}% · Fill {r.FILL_RATE:.2f}% · {int(r.DELIVERED_LINES):,} lines")
            if env in last.index:
                rel = last.loc[env]
                st.caption(f"Last release {rel.STATUS.lower()} · {rel.PROMOTED_AT:%d %b %H:%M}")
            else:
                st.caption("Source of every release")
        if i == 0:
            with cols[1]:
                if st.button("", icon=":material/arrow_forward:", key="rel_UAT", type="primary", width="stretch",
                             help="Run the release train now: DEV → UAT with verification"):
                    run_train()
        elif i == 1:
            with cols[3]:
                if pending.empty:
                    st.button("", icon=":material/lock:", key="rel_PROD", width="stretch", disabled=True,
                              help="Nothing to approve: PROD only accepts a build that passed UAT")
                elif st.button("", icon=":material/arrow_forward:", key="rel_PROD", type="primary", width="stretch",
                               help="Review the UAT-verified release and approve it for PROD"):
                    p = pending.iloc[0]
                    ui.release_decision(int(p.RECOMMENDATION_ID), p.TITLE, p.DESCRIPTION)

    train_tracker()

    left, right = st.columns(2)
    with left, ui.card("Pipeline", f"Hourly task graph in DEV · {running} of {len(tasks)} tasks running"):
        st.dataframe(tasks.assign(NAME=tasks.NAME.str.replace("TASK_", "").str.replace("_", " ").str.title(),
                                  STATE=tasks.STATE.str.title()),
                     hide_index=True, width="stretch",
                     column_config={"NAME": st.column_config.TextColumn("Task"),
                                    "STATE": st.column_config.TextColumn("State")})
        ui.project_control("ops", compact=True)
    with right, ui.card("Promotion log", "Every environment promotion, with its dbt test result"):
        hist = ui.q(f"""
            SELECT promoted_at, source_env || ' → ' || target_env AS release, status, dbt_test_result, promoted_by
            FROM {DB}.L8_ACTION.ENVIRONMENT_REGISTRY ORDER BY promoted_at DESC LIMIT 15
        """)
        st.dataframe(hist, hide_index=True, width="stretch",
                     column_config={"PROMOTED_AT": st.column_config.DatetimeColumn("When", format="DD MMM HH:mm"),
                                    "RELEASE": st.column_config.TextColumn("Release"),
                                    "STATUS": st.column_config.TextColumn("Status"),
                                    "DBT_TEST_RESULT": st.column_config.TextColumn("dbt tests"),
                                    "PROMOTED_BY": st.column_config.TextColumn("By")})

    with ui.card("Decision audit trail", "Every approval, rejection and remediation"):
        st.dataframe(ui.q(f"""
            SELECT action_at, action_type, action_by, role_used, new_status, notes
            FROM {DB}.L8_ACTION.DECISION_AUDIT ORDER BY action_at DESC LIMIT 20
        """), hide_index=True, width="stretch",
            column_config={"ACTION_AT": st.column_config.DatetimeColumn("When", format="DD MMM HH:mm"),
                           "ACTION_TYPE": st.column_config.TextColumn("Action"),
                           "ACTION_BY": st.column_config.TextColumn("By"),
                           "ROLE_USED": st.column_config.TextColumn("Role"),
                           "NEW_STATUS": st.column_config.TextColumn("Outcome"),
                           "NOTES": st.column_config.TextColumn("Note")})


ui.safe(render)
