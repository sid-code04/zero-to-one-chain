import pandas as pd
import streamlit as st

import ui
from ui import DB

ui.header("Action queue", "Recommendations generated from the governed metrics · nothing executes without human approval")

SEVERITY = {"CRITICAL": ":red-badge[Critical]", "HIGH": ":orange-badge[High]", "MEDIUM": ":gray-badge[Medium]"}
STATUS = {"APPROVED": ":green-badge[:material/check: Approved]", "REJECTED": ":gray-badge[:material/close: Rejected]",
          "SUPERSEDED": ":gray-badge[:material/update: Superseded by a newer release]"}


@st.dialog("Record decision")
def decide(rec, status):
    verb = "Approve" if status == "APPROVED" else "Reject"
    st.markdown(f"**{rec.TITLE}**")
    st.caption(rec.RECOMMENDED_ACTION)
    note = st.text_area("Decision note", placeholder="Why? This is stored in the audit trail.", max_chars=500)
    if st.button(f"{verb} recommendation", type="primary", width="stretch"):
        rid = int(rec.RECOMMENDATION_ID)
        ui.run(f"UPDATE {DB}.L8_ACTION.RECOMMENDATIONS SET status = ?, approved_by = CURRENT_USER(), "
               f"approved_at = CURRENT_TIMESTAMP() WHERE recommendation_id = ?", params=[status, rid])
        ui.run(f"INSERT INTO {DB}.L8_ACTION.DECISION_AUDIT (recommendation_id, action_type, action_by, role_used, "
               f"previous_status, new_status, notes) SELECT ?, 'DECISION', CURRENT_USER(), CURRENT_ROLE(), "
               f"'PENDING', ?, ?", params=[rid, status, note or f"{verb}d in Action queue"])
        ui.clear_cache()
        st.toast(f"Recommendation {verb.lower()}d and audited", icon=":material/check_circle:")
        st.rerun()


def render():
    recs = ui.q_live(f"""
        SELECT recommendation_id, severity, category, title, description, recommended_action,
               estimated_impact_usd, status, approved_by, approved_at, rejected_reason
        FROM {DB}.L8_ACTION.RECOMMENDATIONS
        ORDER BY CASE status WHEN 'PENDING' THEN 0 ELSE 1 END,
                 CASE severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 ELSE 3 END, recommendation_id
    """)
    pending = recs[recs.STATUS == "PENDING"]
    with st.container(horizontal=True):
        ui.kpi("Awaiting decision", len(pending), border=True)
        ui.kpi("Critical", int((pending.SEVERITY == "CRITICAL").sum()), border=True)
        ui.kpi("Value of pending actions", ui.money(pending.ESTIMATED_IMPACT_USD.sum()), border=True)
        ui.kpi("Releases awaiting approval", int((pending.CATEGORY == "RELEASE").sum()), border=True)
        ui.kpi("Decided", len(recs) - len(pending), border=True)

    view = st.segmented_control("Show", ["Pending", "Decided", "All"], default="Pending", label_visibility="collapsed")
    shown = {"Pending": pending, "Decided": recs[recs.STATUS != "PENDING"]}.get(view, recs)
    if shown.empty:
        st.caption("Nothing here.")

    for r in shown.itertuples():
        with st.container(border=True):
            body, side = st.columns([4, 1], vertical_alignment="center")
            with body:
                st.markdown(f"{SEVERITY.get(r.SEVERITY, SEVERITY['MEDIUM'])} :blue-badge[{str(r.CATEGORY).title()}] "
                            f"&nbsp; **{r.TITLE}**")
                st.markdown(r.DESCRIPTION)
                st.markdown(f":material/arrow_forward: **{r.RECOMMENDED_ACTION}**")
            with side:
                is_release = r.CATEGORY == "RELEASE"
                if is_release:
                    st.markdown(":material/verified: **UAT verified**")
                else:
                    ui.kpi("Estimated impact", ui.money(r.ESTIMATED_IMPACT_USD))
                if r.STATUS == "PENDING" and ui.READ_ONLY:
                    st.caption("Approvals are disabled in the viewer edition")
                elif r.STATUS == "PENDING" and is_release:
                    if st.button("Review release", key=f"rv{r.RECOMMENDATION_ID}", type="primary",
                                 icon=":material/rocket_launch:"):
                        ui.release_decision(r.RECOMMENDATION_ID, r.TITLE, r.DESCRIPTION)
                elif r.STATUS == "PENDING":
                    with st.container(horizontal=True):
                        if st.button("Approve", key=f"ap{r.RECOMMENDATION_ID}", type="primary"):
                            decide(r, "APPROVED")
                        if st.button("Reject", key=f"rj{r.RECOMMENDATION_ID}"):
                            decide(r, "REJECTED")
                else:
                    st.markdown(STATUS.get(r.STATUS, r.STATUS.title()))
                    if pd.notna(r.APPROVED_BY):
                        st.caption(f"by {r.APPROVED_BY}")
                    elif r.STATUS == "SUPERSEDED" and pd.notna(r.REJECTED_REASON):
                        st.caption(r.REJECTED_REASON)


ui.safe(render)
