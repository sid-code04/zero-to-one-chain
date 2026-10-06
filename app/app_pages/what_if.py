import altair as alt
import pandas as pd
import streamlit as st

import ui
from ui import DB

ui.header("Disruption simulator",
          "Walks the ontology: supplier → parts it sources → open customer orders that need those parts")


def render():
    opts = ui.q(f"""
        SELECT supplier_id, supplier_name, total_revenue_at_risk_usd
        FROM {DB}.L7_INTELLIGENCE.VW_WHATIF_SUPPLIER_DISRUPTION
        WHERE affected_orders > 0 AND supplier_name IS NOT NULL
        ORDER BY total_revenue_at_risk_usd DESC LIMIT 40
    """)
    labels = {f"{r.SUPPLIER_NAME}  ·  {ui.money(r.TOTAL_REVENUE_AT_RISK_USD)} exposed": r.SUPPLIER_ID
              for r in opts.itertuples()}

    with st.container(border=True):
        c_sel, c_weeks = st.columns([3, 2], vertical_alignment="bottom")
        choice = c_sel.selectbox("Supplier goes offline", list(labels.keys()),
                                 help="Top 40 suppliers by revenue exposure")
        weeks = c_weeks.slider("Outage length (weeks)", min_value=1, max_value=8, value=2)
    sid = labels[choice]

    imp = ui.qp(f"SELECT * FROM {DB}.L7_INTELLIGENCE.VW_WHATIF_SUPPLIER_DISRUPTION WHERE supplier_id = ?", (sid,)).iloc[0]
    cust = ui.qp(f"""
        SELECT customer_name, customer_region, service_tier, sla_contract, open_orders,
               revenue_at_risk_usd, earliest_commitment
        FROM {DB}.L7_INTELLIGENCE.VW_WHATIF_CUSTOMER_IMPACT WHERE supplier_id = ?
        ORDER BY earliest_commitment, revenue_at_risk_usd DESC
    """, (sid,))
    start = pd.Timestamp(ui.AS_OF)
    horizon = start + pd.Timedelta(weeks=weeks)
    cust["EARLIEST_COMMITMENT"] = pd.to_datetime(cust.EARLIEST_COMMITMENT)
    cust["IMPACT"] = cust.EARLIEST_COMMITMENT.apply(lambda d: "Hit by outage" if d <= horizon else "Outside window")
    cust["CUSTOMER_REGION"] = ui.title_case(cust.CUSTOMER_REGION)
    hit = cust[cust.IMPACT == "Hit by outage"]
    sla_hits = hit[hit.SLA_CONTRACT == "Yes"]

    with st.container(horizontal=True):
        ui.kpi("Parts sourced from supplier", int(imp.AFFECTED_PARTS), border=True)
        ui.kpi("Open orders needing them", f"{int(imp.AFFECTED_ORDERS):,}", border=True)
        ui.kpi("Customers hit", len(hit), f"{len(sla_hits)} under contractual SLA", delta_color="off",
                  delta_arrow="off", border=True)
        ui.kpi("Revenue at risk in window", ui.money(hit.REVENUE_AT_RISK_USD.sum()),
                  f"of {ui.money(cust.REVENUE_AT_RISK_USD.sum())} total exposure", delta_color="off",
                  delta_arrow="off", border=True)

    dual = imp.DUAL_SOURCE_AVAILABLE == "Yes"
    action = ("activate the qualified alternate source now and shift open POs to it." if dual else
              "no alternate is qualified, so expedite safety stock from other plants and start emergency qualification.")
    ui.finding(f"A **{weeks}-week outage at {imp.SUPPLIER_NAME}** reaches **{len(hit)} customers** before supply resumes, "
               f"{len(sla_hits)} of them under contractual SLA. Recommended: {action}",
               kind="action" if dual else "risk")

    left, right = st.columns([2, 3])
    with left, ui.card("When customers feel it", "Revenue at risk by week of earliest commitment"):
        cust["WEEK"] = cust.EARLIEST_COMMITMENT.dt.to_period("W").dt.start_time
        weekly = cust.groupby(["WEEK", "IMPACT"], as_index=False).REVENUE_AT_RISK_USD.sum()
        bars = alt.Chart(weekly).mark_bar(cornerRadiusTopLeft=2, cornerRadiusTopRight=2).encode(
            x=alt.X("WEEK:T", title=None, axis=alt.Axis(format="%d %b", grid=False)),
            y=alt.Y("REVENUE_AT_RISK_USD:Q", title=None, axis=alt.Axis(format="$.2s")),
            color=alt.Color("IMPACT:N", scale=alt.Scale(domain=["Hit by outage", "Outside window"],
                                                        range=[ui.RED, ui.GREY])),
            tooltip=[alt.Tooltip("WEEK:T", title="Week of", format="%d %b"),
                     alt.Tooltip("REVENUE_AT_RISK_USD:Q", title="Revenue", format="$,.0f")],
        )
        ui.chart(ui.style(bars, 320))
    with right, ui.card("Affected customers", "Earliest commitment first"):
        st.dataframe(cust.drop(columns=["WEEK"]), hide_index=True, width="stretch", height=320,
                     column_order=["IMPACT", "CUSTOMER_NAME", "CUSTOMER_REGION", "SERVICE_TIER", "SLA_CONTRACT",
                                   "OPEN_ORDERS", "REVENUE_AT_RISK_USD", "EARLIEST_COMMITMENT"],
                     column_config={
                         "IMPACT": st.column_config.TextColumn("Impact"),
                         "CUSTOMER_NAME": st.column_config.TextColumn("Customer"),
                         "CUSTOMER_REGION": st.column_config.TextColumn("Region", width="small"),
                         "SERVICE_TIER": st.column_config.TextColumn("Tier", width="small"),
                         "SLA_CONTRACT": st.column_config.TextColumn("SLA", width="small"),
                         "OPEN_ORDERS": st.column_config.NumberColumn("Orders", format="%d", width="small"),
                         "REVENUE_AT_RISK_USD": st.column_config.NumberColumn("Revenue at risk", format="dollar"),
                         "EARLIEST_COMMITMENT": st.column_config.DateColumn("Earliest commit", format="DD MMM YYYY"),
                     })


ui.safe(render)
