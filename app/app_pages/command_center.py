import altair as alt
import streamlit as st

import ui
from ui import DB, TARGETS

head, control = st.columns([3, 1], vertical_alignment="center")
with head:
    ui.header("Command center", "Last full quarter (Jul–Sep 2026) compared with Q2 · delivered order lines only")
with control:
    ui.project_control("cc")


def render():
    monthly = ui.q(f"""
        SELECT DATE_TRUNC('MONTH', actual_delivery_date) AS month,
               AVG(IFF(is_on_time,1,0))*100 AS otd, AVG(IFF(is_otif,1,0))*100 AS otif, AVG(fill_rate_pct) AS fill
        FROM {DB}.L6_SEMANTIC.VW_METRIC_OTD
        WHERE is_delivered AND actual_delivery_date >= '2025-10-01' AND actual_delivery_date < '2026-10-01'
        GROUP BY 1 ORDER BY 1
    """)
    kpi = ui.q(f"""
        SELECT IFF(actual_delivery_date >= '2026-07-01', 'Q3', 'Q2') AS qtr,
               AVG(IFF(is_on_time,1,0))*100 AS otd, AVG(IFF(is_otif,1,0))*100 AS otif, AVG(fill_rate_pct) AS fill
        FROM {DB}.L6_SEMANTIC.VW_METRIC_OTD
        WHERE is_delivered AND actual_delivery_date >= '2026-04-01' AND actual_delivery_date < '2026-10-01'
        GROUP BY 1
    """).set_index("QTR")
    overdue = ui.q(f"""
        SELECT COUNT(*) AS n, SUM(net_value_usd) AS value
        FROM {DB}.L5_CORE.FACT_ORDERS
        WHERE actual_delivery_date IS NULL AND committed_delivery_date < '{ui.AS_OF}'::DATE AND order_status <> 'CANCELLED'
    """).iloc[0]
    c, p = kpi.loc["Q3"], kpi.loc["Q2"]

    with st.container(horizontal=True):
        for label, col, tgt in (("On-time delivery", "OTD", TARGETS["OTD"]), ("OTIF", "OTIF", TARGETS["OTIF"]),
                                ("Fill rate", "FILL", TARGETS["FILL"])):
            ui.kpi(label, f"{c[col]:.1f}%", f"{c[col] - p[col]:+.1f} pts vs Q2", border=True,
                      chart_data=monthly[col].round(1).tolist(), chart_type="line",
                      help=f"{ui.target_note(c[col], tgt)}. Sparkline: last 12 months.")
        ui.kpi("Overdue open orders", ui.money(overdue.VALUE), f"{int(overdue.N):,} lines past commit date",
                  delta_color="off", delta_arrow="off", border=True,
                  help="Open, non-cancelled order lines whose committed delivery date has passed.")

    reg = ui.q(f"""
        SELECT customer_region AS region,
               AVG(IFF(actual_delivery_date >= '2026-07-01', IFF(is_on_time,1,0), NULL))*100 AS q3,
               AVG(IFF(actual_delivery_date <  '2026-07-01', IFF(is_on_time,1,0), NULL))*100 AS prior,
               SUM(IFF(actual_delivery_date >= '2026-07-01' AND NOT is_on_time, net_value_usd, 0)) AS late_value
        FROM {DB}.L6_SEMANTIC.VW_METRIC_OTD
        WHERE is_delivered AND actual_delivery_date >= '2026-01-01' AND actual_delivery_date < '2026-10-01'
        GROUP BY 1
    """)
    reg["DELTA"] = reg.Q3 - reg.PRIOR
    worst = reg.sort_values("DELTA").iloc[0]
    if worst.DELTA < -3:
        others = reg[reg.REGION != worst.REGION]
        ui.finding(f"**{worst.REGION.title()} on-time delivery fell from {worst.PRIOR:.1f}% to {worst.Q3:.1f}% in Q3** "
                   f"({worst.DELTA:+.1f} pts), while {' and '.join(others.REGION.str.title())} held within "
                   f"{others.DELTA.abs().max():.1f} pts. One region explains the global decline; "
                   f"{ui.money(worst.LATE_VALUE)} of Q3 deliveries arrived late there.")
    else:
        ui.finding("All regions are within 3 pts of their first-half performance.", kind="ok")

    trend = ui.q(f"""
        SELECT DATE_TRUNC('MONTH', actual_delivery_date) AS month, customer_region AS region,
               ROUND(AVG(IFF(is_on_time,1,0))*100,1) AS otd
        FROM {DB}.L6_SEMANTIC.VW_METRIC_OTD
        WHERE is_delivered AND actual_delivery_date >= '2025-10-01' AND actual_delivery_date < '2026-10-01'
        GROUP BY 1,2 ORDER BY 1
    """)
    left, right = st.columns([5, 3])
    with left, ui.card("On-time delivery by region", "Monthly, last 12 months · dashed line is the 95% target"):
        line = alt.Chart(trend).mark_line(point=True, strokeWidth=2.5, interpolate="monotone").encode(
            x=alt.X("MONTH:T", title=None, axis=alt.Axis(format="%b", grid=False)),
            y=alt.Y("OTD:Q", title=None, scale=alt.Scale(domain=[50, 100]), axis=alt.Axis(format=".0f")),
            color=alt.Color("REGION:N", scale=ui.REGION_SCALE),
            tooltip=[alt.Tooltip("MONTH:T", title="Month", format="%b %Y"), alt.Tooltip("REGION:N", title="Region"),
                     alt.Tooltip("OTD:Q", title="OTD %")],
        )
        ui.chart(ui.style(line + ui.rule(TARGETS["OTD"], ui.GREY, "Target 95%"), 320))
    with right, ui.card("Region scorecard", "Jan–Jun average vs Q3 2026"):
        show = reg.assign(REGION=ui.title_case(reg.REGION)).sort_values("DELTA")
        st.dataframe(show[["REGION", "PRIOR", "Q3", "DELTA"]], hide_index=True, width="stretch",
                     column_config={
                         "REGION": st.column_config.TextColumn("Region"),
                         "PRIOR": st.column_config.NumberColumn("H1 OTD", format="%.1f%%"),
                         "Q3": st.column_config.ProgressColumn("Q3 OTD", min_value=0, max_value=100, format="%.1f%%"),
                         "DELTA": st.column_config.NumberColumn("Change", format="%+.1f pts"),
                     })
        persona = st.session_state.get("persona", "Planning")
        st.markdown(f"**{persona} priorities**")
        st.markdown({
            "Planning": "- Re-plan APAC commit dates for Q4\n- Protect Platinum and Gold customers from further SLA breaches",
            "Procurement": "- Recover or replace the chronically late suppliers\n- Qualify second sources for single-sourced parts",
            "Logistics": "- Reduce APAC ocean exposure\n- Use air for priority orders until the lane recovers",
        }[persona])

    st.markdown("**Investigate**")
    with st.container(horizontal=True):
        for path, title, blurb, icon in (
            ("app_pages/delivery.py", "Delivery root cause", "Which lane broke, and which customers felt it", ":material/local_shipping:"),
            ("app_pages/inventory.py", "Inventory exposure", "Where buffers are below safety stock", ":material/inventory_2:"),
            ("app_pages/suppliers.py", "Supplier risk", "Late suppliers and spend exposed", ":material/factory:"),
            ("app_pages/actions.py", "Pending decisions", "Approve or reject recommended actions", ":material/task_alt:"),
        ):
            with st.container(border=True):
                ui.link(path, title, icon=icon)
                st.caption(blurb)


ui.safe(render)
