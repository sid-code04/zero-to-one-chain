import altair as alt
import streamlit as st

import ui
from ui import DB

ui.header("Delivery", "Root cause of the Q3 on-time decline · APAC customer orders, Jan–Sep 2026")


def render():
    mode = ui.q(f"""
        SELECT INITCAP(shipping_method) AS method,
               IFF(order_date >= '2026-07-01', 'Q3 2026', 'H1 2026') AS period,
               ROUND(AVG(IFF(is_on_time,1,0))*100,1) AS otd, COUNT(*) AS lines
        FROM {DB}.L6_SEMANTIC.VW_METRIC_OTD
        WHERE is_delivered AND customer_region = 'APAC' AND order_date >= '2026-01-01'
        GROUP BY 1,2
    """)
    piv = mode.pivot(index="METHOD", columns="PERIOD", values="OTD").reset_index()
    piv["DROP"] = piv["Q3 2026"] - piv["H1 2026"]
    top = piv.sort_values("DROP").iloc[0]
    rest = piv[piv.METHOD != top.METHOD]
    q3_lines = mode[(mode.PERIOD == "Q3 2026")].set_index("METHOD").LINES
    share = q3_lines.get(top.METHOD, 0) / q3_lines.sum() * 100

    ui.finding(f"**{top.METHOD} shipments to APAC collapsed from {top['H1 2026']:.1f}% to {top['Q3 2026']:.1f}% on time** "
               f"({top.DROP:+.1f} pts) and carry {share:.0f}% of APAC volume. Other methods moved at most "
               f"{rest.DROP.abs().max():.1f} pts, so this is a lane problem, not a plant or customer problem.")

    sla = ui.q(f"""
        SELECT customer_name, INITCAP(customer_region) AS region, service_tier, COUNT(*) AS lines,
               AVG(IFF(is_on_time,1,0))*100 AS otd,
               SUM(IFF(NOT is_on_time, net_value_usd, 0)) AS late_value
        FROM {DB}.L6_SEMANTIC.VW_METRIC_OTD
        WHERE is_delivered AND order_date >= '2026-07-01' AND service_tier IN ('Platinum','Gold')
        GROUP BY 1,2,3 HAVING COUNT(*) >= 5 AND AVG(IFF(is_on_time,1,0)) < 0.90
        ORDER BY otd
    """)
    with st.container(horizontal=True):
        ui.kpi(f"APAC {top.METHOD.lower()} OTD, Q3", f"{top['Q3 2026']:.1f}%", f"{top.DROP:+.1f} pts vs H1", border=True)
        ui.kpi("APAC lines on this lane, Q3", f"{int(q3_lines.get(top.METHOD, 0)):,}", f"{share:.0f}% of APAC volume",
                  delta_color="off", delta_arrow="off", border=True)
        ui.kpi("Strategic customers below 90%", len(sla), f"{(sla.REGION == 'Apac').sum()} of them in APAC",
                  delta_color="off", delta_arrow="off", border=True)
        ui.kpi("Late value at those customers", ui.money(sla.LATE_VALUE.sum()), border=True)

    left, right = st.columns([1, 1])
    with left, ui.card("APAC on-time delivery by shipping method", "H1 2026 vs Q3 2026, by order date"):
        bars = alt.Chart(mode).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
            x=alt.X("METHOD:N", title=None, sort=alt.SortField("METHOD"), axis=alt.Axis(labelAngle=0)),
            xOffset=alt.XOffset("PERIOD:N", sort=["H1 2026", "Q3 2026"]),
            y=alt.Y("OTD:Q", title=None, scale=alt.Scale(domain=[0, 100])),
            color=alt.Color("PERIOD:N", scale=alt.Scale(domain=["H1 2026", "Q3 2026"], range=[ui.NAVY, ui.ORANGE])),
            tooltip=[alt.Tooltip("METHOD:N", title="Method"), alt.Tooltip("PERIOD:N", title="Period"),
                     alt.Tooltip("OTD:Q", title="OTD %"), alt.Tooltip("LINES:Q", title="Lines", format=",")],
        )
        labels = bars.mark_text(dy=-7, fontSize=11, color="#11567F").encode(text=alt.Text("OTD:Q", format=".0f"))
        ui.chart(ui.style(bars + labels + ui.rule(95, ui.GREY, "Target 95%"), 330))

    with right, ui.card("Strategic customers breaching SLA", "Platinum and Gold accounts below 90% on Q3 orders, all regions"):
        st.dataframe(sla.head(12), hide_index=True, width="stretch", height=330,
                     column_config={
                         "CUSTOMER_NAME": st.column_config.TextColumn("Customer"),
                         "REGION": st.column_config.TextColumn("Region", width="small"),
                         "SERVICE_TIER": st.column_config.TextColumn("Tier", width="small"),
                         "LINES": st.column_config.NumberColumn("Lines", format="%d", width="small"),
                         "OTD": st.column_config.ProgressColumn("OTD", min_value=0, max_value=100, format="%.0f%%"),
                         "LATE_VALUE": st.column_config.NumberColumn("Late value", format="dollar"),
                     })
        others = sla[sla.REGION != "Apac"]
        if others.empty:
            st.caption("No Americas or EMEA strategic customer is below 90%: the impact is confined to APAC.")

    ui.finding("Move Platinum and Gold APAC orders off the ocean lane until it recovers, and re-baseline "
               "APAC commit dates so customers get a promise the network can keep.", kind="action")


ui.safe(render)
