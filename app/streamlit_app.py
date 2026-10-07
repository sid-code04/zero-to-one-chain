import streamlit as st

import ui

st.set_page_config(page_title="Zero to One Chain · Supply Chain Decision Twin",
                   page_icon=":material/hub:", layout="wide")

ui.conn()

SECTIONS = {
    "Ask": [
        st.Page("app_pages/assistant.py", title="Ask the Twin", icon=":material/smart_toy:"),
    ],
    "Performance": [
        st.Page("app_pages/command_center.py", title="Command center", icon=":material/space_dashboard:", default=True),
        st.Page("app_pages/delivery.py", title="Delivery", icon=":material/local_shipping:"),
        st.Page("app_pages/inventory.py", title="Inventory", icon=":material/inventory_2:"),
        st.Page("app_pages/suppliers.py", title="Suppliers", icon=":material/factory:"),
    ],
    "Decide": [
        st.Page("app_pages/what_if.py", title="Disruption simulator", icon=":material/science:"),
        st.Page("app_pages/actions.py", title="Action queue", icon=":material/task_alt:"),
    ],
    "Govern": [
        st.Page("app_pages/trust.py", title="Trust & quality", icon=":material/verified_user:"),
        st.Page("app_pages/operations.py", title="Operations", icon=":material/settings_suggest:"),
    ],
}

# The built-in menu always renders at the very top of the sidebar, so it is hidden and drawn below
# the brand and project status instead.
page = st.navigation(SECTIONS, position="hidden")

with st.sidebar:
    st.markdown("### :material/hub: Zero to One Chain")
    st.caption("Supply chain decision twin")
    st.session_state.persona = st.segmented_control(
        "Viewing as", ["Planning", "Procurement", "Logistics"],
        default=st.session_state.get("persona") or "Planning", key="persona_pick") or "Planning"
    st.caption("Every persona reads the same governed metric definitions.")
    ui.project_control("sidebar", compact=True)

    for section, pages in SECTIONS.items():
        st.caption(section.upper())
        for p in pages:
            st.page_link(p, label=p.title, icon=p.icon, width="stretch")

    st.button("Refresh data", icon=":material/refresh:", on_click=ui.clear_cache, width="stretch")
    st.caption(f"Business date {ui.AS_OF} · " + ("Viewer edition (read-only)" if ui.READ_ONLY else "Environment DEV"))

page.run()
