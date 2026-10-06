import altair as alt
import streamlit as st

import ui
from ui import DB

ui.header("Inventory", f"Snapshot {ui.AS_OF} · days of inventory = on-hand ÷ average daily demand · safety stock = 7 days")


def render():
    snap = ui.q(f"""
        SELECT region, AVG(days_of_inventory) AS doi,
               COUNT_IF(stock_status = 'STOCKOUT') AS stockouts,
               COUNT_IF(stock_status IN ('STOCKOUT','BELOW_SAFETY')) AS at_risk,
               COUNT(*) AS locations, SUM(inventory_value_usd) AS value
        FROM {DB}.L6_SEMANTIC.VW_METRIC_INVENTORY
        WHERE snapshot_date = '{ui.AS_OF}'
        GROUP BY 1
    """)
    trend = ui.q(f"""
        SELECT snapshot_month AS month, region, ROUND(AVG(days_of_inventory),1) AS doi
        FROM {DB}.L6_SEMANTIC.VW_METRIC_INVENTORY
        WHERE snapshot_date >= '2025-11-01' GROUP BY 1,2 ORDER BY 1
    """)
    tot = snap.sum(numeric_only=True)
    net_doi = (snap.DOI * snap.LOCATIONS).sum() / tot.LOCATIONS
    network = trend.groupby("MONTH").DOI.mean().round(1).tolist()

    with st.container(horizontal=True):
        ui.kpi("Inventory value", ui.money(tot.VALUE), border=True)
        ui.kpi("Network days of inventory", f"{net_doi:.1f} days", border=True, chart_data=network, chart_type="line",
                  help="Sparkline: monthly average, last 12 months")
        ui.kpi("Below safety stock", f"{int(tot.AT_RISK):,}", f"of {int(tot.LOCATIONS):,} part-locations",
                  delta_color="off", delta_arrow="off", border=True)
        ui.kpi("Stockouts today", f"{int(tot.STOCKOUTS):,}", border=True)

    worst = snap.sort_values("DOI").iloc[0]
    others = snap[snap.REGION != worst.REGION].DOI.mean()
    if worst.DOI < others - 2:
        ui.finding(f"**{worst.REGION.title()} plants hold {worst.DOI:.1f} days of cover against {others:.1f} elsewhere**, "
                   f"with {int(worst.AT_RISK)} part-locations below safety stock. Late inbound ocean freight is "
                   "eating the buffer: the same disruption shown on the Delivery page.")
    else:
        ui.finding("Days of inventory is balanced across regions.", kind="ok")

    left, right = st.columns([5, 3])
    with left, ui.card("Days of inventory by region", "Monthly average · red dashed line is safety stock"):
        line = alt.Chart(trend).mark_line(point=True, strokeWidth=2.5, interpolate="monotone").encode(
            x=alt.X("MONTH:T", title=None, axis=alt.Axis(format="%b", grid=False)),
            y=alt.Y("DOI:Q", title=None, scale=alt.Scale(domain=[0, 20])),
            color=alt.Color("REGION:N", scale=ui.REGION_SCALE),
            tooltip=[alt.Tooltip("MONTH:T", title="Month", format="%b %Y"), alt.Tooltip("REGION:N", title="Region"),
                     alt.Tooltip("DOI:Q", title="Days")],
        )
        ui.chart(ui.style(line + ui.rule(7, ui.RED, "Safety stock 7 days"), 320))
    with right, ui.card("Region snapshot", "Today"):
        show = snap.assign(REGION=ui.title_case(snap.REGION)).sort_values("DOI")
        st.dataframe(show[["REGION", "DOI", "AT_RISK", "STOCKOUTS", "VALUE"]], hide_index=True, width="stretch",
                     column_config={
                         "REGION": st.column_config.TextColumn("Region"),
                         "DOI": st.column_config.ProgressColumn("Days", min_value=0, max_value=20, format="%.1f"),
                         "AT_RISK": st.column_config.NumberColumn("Below safety", format="%d"),
                         "STOCKOUTS": st.column_config.NumberColumn("Stockouts", format="%d"),
                         "VALUE": st.column_config.NumberColumn("Value", format="compact"),
                     })

    exp = ui.q(f"""
        SELECT plant_name, region, part_name, material_number, abc_class, stock_status,
               days_of_inventory, on_hand_qty, safety_stock_qty, in_transit_qty
        FROM {DB}.L6_SEMANTIC.VW_METRIC_INVENTORY
        WHERE snapshot_date = '{ui.AS_OF}' AND stock_status IN ('STOCKOUT','BELOW_SAFETY')
        ORDER BY days_of_inventory, abc_class LIMIT 50
    """)
    exp["REGION"] = ui.title_case(exp.REGION)
    exp["STOCK_STATUS"] = exp.STOCK_STATUS.map({"STOCKOUT": "Stockout", "BELOW_SAFETY": "Below safety"})
    with ui.card("Expedite list", "Lowest cover first · A-class parts are revenue-critical"):
        st.dataframe(exp, hide_index=True, width="stretch", height=380,
                     column_config={
                         "PLANT_NAME": st.column_config.TextColumn("Plant"),
                         "REGION": st.column_config.TextColumn("Region", width="small"),
                         "PART_NAME": st.column_config.TextColumn("Part"),
                         "MATERIAL_NUMBER": st.column_config.TextColumn("Material"),
                         "ABC_CLASS": st.column_config.TextColumn("Class", width="small"),
                         "STOCK_STATUS": st.column_config.TextColumn("Status"),
                         "DAYS_OF_INVENTORY": st.column_config.ProgressColumn("Days of cover", min_value=0, max_value=7,
                                                                              format="%.1f"),
                         "ON_HAND_QTY": st.column_config.NumberColumn("On hand", format="localized"),
                         "SAFETY_STOCK_QTY": st.column_config.NumberColumn("Safety stock", format="localized"),
                         "IN_TRANSIT_QTY": st.column_config.NumberColumn("In transit", format="localized"),
                     })


ui.safe(render)
