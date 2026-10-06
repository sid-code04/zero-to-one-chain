import streamlit as st

import ui
from ui import DB

ui.header("Trust & quality", "Why the numbers on every page can be believed")


def render():
    proof = ui.q(f"""
        SELECT metric_name, planner_result, procurement_result, logistics_result, all_match
        FROM {DB}.L6_SEMANTIC.CONSISTENCY_PROOF ORDER BY proof_id
    """)
    dq = ui.q(f"""
        SELECT source_table, rule_name, severity, COUNT(*) AS records, COUNT_IF(resolved_at IS NULL) AS open_records
        FROM {DB}.L3_VALIDATE.DQ_QUARANTINE GROUP BY 1,2,3 ORDER BY open_records DESC, records DESC
    """)
    open_n = int(dq.OPEN_RECORDS.sum()) if len(dq) else 0
    critical = int(dq[dq.SEVERITY == "CRITICAL"].OPEN_RECORDS.sum()) if len(dq) else 0
    matched = int(proof.ALL_MATCH.sum())

    with st.container(horizontal=True):
        ui.kpi("Metrics consistent across personas", f"{matched} of {len(proof)}", border=True)
        ui.kpi("Open data quality issues", open_n, border=True)
        ui.kpi("Critical issues", critical, border=True)
        ui.kpi("Promotion gate", "Blocked" if critical else "Open", border=True,
                  help="UAT and PROD releases are refused while any critical issue is open.")

    if matched == len(proof) and not critical:
        ui.finding(f"**One question, one answer.** All {len(proof)} canonical metrics return identical values when "
                   "Planning, Procurement and Logistics ask them, and the release gate is clear.", kind="ok")
    elif critical:
        ui.finding(f"**{critical} critical records are quarantined**, so promotion to UAT and PROD is blocked "
                   "until they are remediated.")

    left, right = st.columns([3, 2])
    with left, ui.card("Consistency proof", "Same metric, asked by three personas through the semantic view"):
        st.dataframe(proof, hide_index=True, width="stretch",
                     column_config={
                         "METRIC_NAME": st.column_config.TextColumn("Metric"),
                         "PLANNER_RESULT": st.column_config.NumberColumn("Planning", format="%.2f"),
                         "PROCUREMENT_RESULT": st.column_config.NumberColumn("Procurement", format="%.2f"),
                         "LOGISTICS_RESULT": st.column_config.NumberColumn("Logistics", format="%.2f"),
                         "ALL_MATCH": st.column_config.CheckboxColumn("Identical", width="small"),
                     })
    with right, ui.card("Access controls in force", "Enforced in Snowflake, not in the app"):
        st.markdown(
            ":material/visibility_off: **Masking**  \nSupplier spend visible to Procurement only; contact emails "
            "masked for non-admin roles\n\n"
            ":material/filter_alt: **Row access**  \nLogistics sees AMERICAS and EMEA customer rows only\n\n"
            ":material/sell: **Classification**  \nPII and FINANCIAL tags on contact and price columns\n\n"
            ":material/monitor_heart: **Data metric functions**  \nNegative values, out-of-range rates and "
            "orphan suppliers measured on schedule")

    with ui.card("Data quality quarantine", "Records held back from the core model by validation rules"):
        dq_show = dq.assign(SEVERITY=ui.title_case(dq.SEVERITY), RULE_NAME=ui.title_case(dq.RULE_NAME))
        st.dataframe(dq_show, hide_index=True, width="stretch",
                     column_config={
                         "SOURCE_TABLE": st.column_config.TextColumn("Source table"),
                         "RULE_NAME": st.column_config.TextColumn("Rule"),
                         "SEVERITY": st.column_config.TextColumn("Severity", width="small"),
                         "RECORDS": st.column_config.NumberColumn("Caught", format="%d"),
                         "OPEN_RECORDS": st.column_config.NumberColumn("Still open", format="%d"),
                     })
        if open_n and not ui.READ_ONLY and st.button("Remediate quarantined records", icon=":material/build:", type="primary"):
            with st.spinner("Applying remediation rules"):
                msg = ui.run(f"CALL {DB}.L3_VALIDATE.SP_RESOLVE_QUARANTINE()")[0][0]
            ui.clear_cache()
            st.toast(msg, icon=":material/check_circle:")
            st.rerun()


ui.safe(render)
