import altair as alt
import streamlit as st

import ui
from ui import DB

ui.header("Suppliers", "Inbound on-time delivery on received purchase-order lines placed since July 2026")


def render():
    sup = ui.q(f"""
        SELECT p.supplier_id, s.supplier_name, s.region, s.tier, s.dual_source_available AS dual_source,
               s.health_tier, COUNT(*) AS po_lines,
               AVG(IFF(p.is_on_time,1,0))*100 AS inbound_otd,
               AVG(p.delivery_variance_days) AS avg_days_late,
               SUM(p.landed_cost_usd) AS spend
        FROM {DB}.PUBLIC_L5_CORE.FACT_PURCHASE_ORDERS p
        JOIN {DB}.PUBLIC_L5_CORE.DIM_SUPPLIER s ON s.supplier_id = p.supplier_id
        WHERE p.actual_delivery_date IS NOT NULL AND p.po_date >= '2026-07-01'
        GROUP BY 1,2,3,4,5,6 HAVING COUNT(*) >= 10
    """)
    sup["REGION"] = ui.title_case(sup.REGION)
    bad = sup[sup.INBOUND_OTD < 70].sort_values("INBOUND_OTD")
    single = bad[bad.DUAL_SOURCE == "No"]
    median = sup.INBOUND_OTD.median()

    with st.container(horizontal=True):
        ui.kpi("Active suppliers", f"{len(sup):,}", f"median inbound OTD {median:.1f}%", delta_color="off",
                  delta_arrow="off", border=True)
        ui.kpi("Suppliers below 70% on time", len(bad), border=True)
        ui.kpi("Q3 spend with them", ui.money(bad.SPEND.sum()),
                  f"{bad.SPEND.sum() / sup.SPEND.sum() * 100:.1f}% of total", delta_color="off", delta_arrow="off",
                  border=True)
        ui.kpi("Single-sourced", len(single), "no qualified alternate", delta_color="off", delta_arrow="off",
                  border=True)

    ui.finding(f"**{len(bad)} suppliers deliver below 70% on time against a network median of {median:.1f}%.** "
               f"They hold {ui.money(bad.SPEND.sum())} of Q3 spend, and {len(single)} have no qualified second source: "
               "a disruption at any of those stops supply outright. Test one in the disruption simulator.")

    left, right = st.columns([3, 2])
    with left, ui.card("Suppliers needing intervention", "Sorted by inbound on-time delivery"):
        st.dataframe(bad[["SUPPLIER_NAME", "REGION", "TIER", "INBOUND_OTD", "AVG_DAYS_LATE", "SPEND", "DUAL_SOURCE"]],
                     hide_index=True, width="stretch",
                     column_config={
                         "SUPPLIER_NAME": st.column_config.TextColumn("Supplier"),
                         "REGION": st.column_config.TextColumn("Region", width="small"),
                         "TIER": st.column_config.TextColumn("Tier", width="small"),
                         "INBOUND_OTD": st.column_config.ProgressColumn("Inbound OTD", min_value=0, max_value=100,
                                                                        format="%.0f%%"),
                         "AVG_DAYS_LATE": st.column_config.NumberColumn("Avg days late", format="%.1f"),
                         "SPEND": st.column_config.NumberColumn("Q3 spend", format="compact"),
                         "DUAL_SOURCE": st.column_config.TextColumn("Alternate source", width="small"),
                     })
        ui.link("app_pages/what_if.py", "Simulate an outage at one of these suppliers",
                     icon=":material/science:")
    with right, ui.card("Spend vs reliability", "Each dot is a supplier · red dots are below 70%"):
        sup["STATUS"] = sup.INBOUND_OTD.apply(lambda v: "Below 70%" if v < 70 else "Healthy")
        dots = alt.Chart(sup).mark_circle(opacity=0.8, stroke="white", strokeWidth=0.5).encode(
            x=alt.X("SPEND:Q", title="Q3 spend", axis=alt.Axis(format="$.2s")),
            y=alt.Y("INBOUND_OTD:Q", title="Inbound OTD %", scale=alt.Scale(domain=[30, 100])),
            size=alt.Size("PO_LINES:Q", legend=None, scale=alt.Scale(range=[30, 220])),
            color=alt.Color("STATUS:N", scale=alt.Scale(domain=["Healthy", "Below 70%"], range=[ui.GREY, ui.RED])),
            tooltip=[alt.Tooltip("SUPPLIER_NAME:N", title="Supplier"),
                     alt.Tooltip("INBOUND_OTD:Q", title="OTD %", format=".1f"),
                     alt.Tooltip("SPEND:Q", title="Spend", format="$,.0f"),
                     alt.Tooltip("DUAL_SOURCE:N", title="Alternate source")],
        )
        ui.chart(ui.style(dots + ui.rule(70, ui.RED, "70% threshold"), 340))


ui.safe(render)
