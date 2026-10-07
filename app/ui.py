"""Shared data access, formatting and visual language for every page."""
import datetime
import decimal
import functools
import inspect
import os

import altair as alt
import pandas as pd
import streamlit as st

DB = "ZERO_TO_ONE_CHAIN"
# The shared deployment ships a `viewer.flag` file: every write action is hidden and refused. The admin
# copy in the workspace has no flag, so it keeps the Start/Stop, Release and Approve controls.
READ_ONLY = os.path.exists(os.path.join(os.path.dirname(os.path.abspath(__file__)), "viewer.flag"))
AS_OF = "2026-10-05"
TARGETS = {"OTD": 95.0, "OTIF": 90.0, "FILL": 98.0}

# One palette, used everywhere: brand blue, navy, accent orange, semantic green/red, neutral grey.
BLUE, NAVY, ORANGE, GREEN, RED, GREY = "#29B5E8", "#11567F", "#FF8B00", "#36B37E", "#DE350B", "#A5B4C3"
REGION_SCALE = alt.Scale(domain=["AMERICAS", "EMEA", "APAC"], range=[BLUE, NAVY, ORANGE])


def conn():
    if "conn" not in st.session_state:
        st.session_state.conn = st.connection("snowflake", ttl=os.getenv("SNOWFLAKE_CONNECTION_TTL"))
    return st.session_state.conn


# ---------------------------------------------------------------- data access
def _normalize(df: pd.DataFrame) -> pd.DataFrame:
    """The connector returns NUMBER(p,s) as decimal.Decimal and DATE as datetime.date (object dtype).
    Convert them once here so every page gets float and datetime64 columns that pandas and Altair can use."""
    for col in df.columns[df.dtypes == object]:
        sample = df[col].dropna()
        if sample.empty:
            continue
        first = sample.iloc[0]
        if isinstance(first, decimal.Decimal):
            df[col] = pd.to_numeric(df[col], errors="coerce").astype(float)
        elif isinstance(first, datetime.date):
            df[col] = pd.to_datetime(df[col], errors="coerce")
    return df


@st.cache_data(ttl=600, show_spinner=False)
def q(sql: str) -> pd.DataFrame:
    return _normalize(conn().query(sql, ttl=0))


@st.cache_data(ttl=15, show_spinner=False)
def q_live(sql: str) -> pd.DataFrame:
    """Operational state (task runs, releases, approvals) that changes outside the app: cached for seconds."""
    return _normalize(conn().query(sql, ttl=0))


@st.cache_data(ttl=600, show_spinner=False)
def qp(sql: str, params: tuple) -> pd.DataFrame:
    """Cached, parameterized read (qmark binding) for user-selected values."""
    return _normalize(conn().session().sql(sql, params=list(params)).to_pandas())


def run(sql: str, params=None):
    """Uncached execution for actions (CALL / UPDATE). Refused in the read-only viewer edition."""
    if READ_ONLY:
        raise PermissionError("This is the read-only viewer edition: actions are disabled.")
    return conn().session().sql(sql, params=params).collect()


def clear_cache():
    q.clear()
    qp.clear()
    q_live.clear()


# ---------------------------------------------------------------- version compatibility
# The container runtime ships whichever Streamlit it has pre-installed (>= 1.50) unless a
# package repository is attached, so newer keyword arguments are passed only when supported.
@functools.cache
def _params(fn) -> frozenset:
    return frozenset(inspect.signature(fn).parameters)


def _supported(fn, kwargs: dict) -> dict:
    return {k: v for k, v in kwargs.items() if k in _params(fn)}


def kpi(label, value, delta=None, **kwargs):
    """st.metric; drops options (e.g. delta_arrow) that the running Streamlit lacks."""
    return st.metric(label, value, delta, **_supported(st.metric, kwargs))


def chart(c):
    """Full-width Altair chart on any Streamlit >= 1.50."""
    if "width" in _params(st.altair_chart):
        return st.altair_chart(c, width="stretch")
    return st.altair_chart(c, use_container_width=True)


# ---------------------------------------------------------------- whole-project switch
ENVS = {"DEV": DB, "UAT": f"{DB}_UAT", "PROD": f"{DB}_PROD"}
_STATE_SQL = " UNION ALL ".join(
    f"SELECT '{env}' AS env, COUNT_IF(state = 'started') AS running, COUNT(*) AS total "
    f"FROM TABLE({db}.INFORMATION_SCHEMA.TASK_DEPENDENTS("
    f"TASK_NAME => '{db}.L3_VALIDATE.TASK_DQ_REFRESH', RECURSIVE => TRUE))"
    for env, db in ENVS.items())


def project_state() -> tuple[str, pd.DataFrame]:
    """RUNNING when DEV and PROD pipelines are fully on, STOPPED when every environment is off."""
    df = q_live(_STATE_SQL).set_index("ENV")
    running = df.RUNNING.sum()
    if running == 0:
        return "STOPPED", df
    live = df.loc[["DEV", "PROD"]]
    return ("RUNNING" if (live.RUNNING == live.TOTAL).all() else "PARTIAL"), df


@st.dialog("Confirm project switch")
def _confirm(action: str):
    if action == "STOP":
        st.markdown("Suspend **every scheduled task and alert in DEV, UAT and PROD**. "
                    "Data, dashboards, agents and history stay intact; nothing is dropped. "
                    "Warehouse consumption from the pipeline stops.")
    else:
        st.markdown("Resume the hourly pipeline and alerts in **DEV and PROD**. DEV's pipeline ends with "
                    "the release train: a change goes to UAT automatically, and PROD waits for your approval.")
    if st.button(f"{action.title()} project", type="primary", width="stretch",
                 icon=":material/stop:" if action == "STOP" else ":material/play_arrow:"):
        with st.spinner(f"{action.title()}ping all environments" if action == "STOP" else "Starting"):
            msg = run(f"CALL {DB}.L8_ACTION.SP_PROJECT_CONTROL(?)", params=[action])[0][0]
        clear_cache()
        st.session_state.project_msg = msg
        st.rerun()


def project_control(key: str, compact: bool = False):
    """Status of the whole project plus the one button that flips it."""
    try:
        state, df = project_state()
    except Exception as exc:  # noqa: BLE001
        st.caption(f"Pipeline status unavailable: {exc}")
        return
    badge = {"RUNNING": ":green-badge[:material/play_circle: Running]",
             "STOPPED": ":gray-badge[:material/stop_circle: Stopped]",
             "PARTIAL": ":orange-badge[:material/warning: Partially running]"}[state]
    detail = " · ".join(f"{e} {int(r.RUNNING)}/{int(r.TOTAL)}" for e, r in df.iterrows())
    action = "START" if state == "STOPPED" else "STOP"
    with st.container(border=not compact):
        if compact:
            st.markdown(f"**Project** &nbsp; {badge}")
        else:
            st.markdown(f"**Project pipeline** &nbsp; {badge}")
        st.caption(f"Tasks running: {detail}")
        if READ_ONLY:
            return
        if st.button("Stop project" if action == "STOP" else "Start project", key=f"{key}_{action}",
                     icon=":material/stop:" if action == "STOP" else ":material/play_arrow:",
                     type="secondary" if action == "STOP" else "primary", width="stretch"):
            _confirm(action)
    msg = st.session_state.pop("project_msg", None) if compact else None  # sidebar renders on every page
    if msg:
        st.toast(msg, icon=":material/check_circle:" if msg.startswith("SUCCESS") else ":material/warning:")


# ---------------------------------------------------------------- release train
TRAIN_STATUS = {
    "SKIPPED_NO_CHANGE": ":gray-badge[No change]",
    "BLOCKED": ":red-badge[Blocked by data quality]",
    "RELEASING_UAT": ":blue-badge[:material/sync: Releasing to UAT]",
    "UAT_FAILED": ":red-badge[UAT checks failed]",
    "AWAITING_APPROVAL": ":orange-badge[:material/pending: Awaiting approval]",
    "RELEASING_PROD": ":blue-badge[:material/sync: Releasing to PROD]",
    "PROD_RELEASED": ":green-badge[:material/check_circle: In PROD]",
    "PROD_FAILED": ":red-badge[PROD release failed]",
    "REJECTED": ":gray-badge[Rejected]",
    "SUPERSEDED": ":gray-badge[Superseded]",
}


@st.dialog("Release to PROD", width="large")
def release_decision(rec_id: int, title: str, description: str):
    """The only path to PROD: a recorded human decision on a UAT-verified build."""
    st.markdown(f"**{title}**")
    st.markdown(description)
    st.caption("Approving runs UAT → PROD: data, dbt models and tests, every layer, semantic view and agents. "
               "It is refused if DEV changed after this build was verified in UAT.")
    note = st.text_area("Decision note", placeholder="Stored in the audit trail with your name and role",
                        max_chars=500, key=f"note_{rec_id}")
    def show_result(msg):
        (st.success if msg.startswith(("SUCCESS", "REJECTED")) else st.warning)(msg)
        if st.button("Close", key=f"close_{rec_id}", width="stretch"):
            st.session_state.pop(f"done_{rec_id}", None)
            st.rerun()

    if st.session_state.get(f"done_{rec_id}"):
        show_result(st.session_state[f"done_{rec_id}"])
        return
    approve, reject = st.columns(2)
    choice = None
    if approve.button("Approve and release", type="primary", icon=":material/rocket_launch:", width="stretch"):
        choice = "APPROVE"
    if reject.button("Reject", icon=":material/block:", width="stretch"):
        choice = "REJECT"
    if choice:
        label = "Releasing UAT → PROD (about 5 minutes)" if choice == "APPROVE" else "Recording rejection"
        with st.status(label, expanded=True) as status:
            if choice == "APPROVE":
                st.write("Checking DEV still matches the verified build, then: quality gate, data, dbt build and "
                         "tests, full-stack deploy")
            msg = str(run(f"CALL {DB}.L8_ACTION.SP_DECIDE_RELEASE(?, ?, ?)",
                          params=[int(rec_id), choice, note])[0][0])
            ok = msg.startswith(("SUCCESS", "REJECTED"))
            status.update(label="Done" if ok else "Not released", state="complete" if ok else "error")
        clear_cache()
        st.session_state[f"done_{rec_id}"] = msg
        show_result(msg)


def link(page: str, label: str, icon: str):
    """Page link that degrades to plain text instead of failing the section around it."""
    try:
        st.page_link(page, label=label, icon=icon)
    except Exception:  # noqa: BLE001
        st.markdown(f"{icon} {label}")


def safe(render):
    """Render a section; a failure is contained instead of breaking the page."""
    try:
        render()
    except Exception as exc:  # noqa: BLE001
        st.error("This section could not load. Use **Refresh data** in the sidebar to retry.",
                 icon=":material/error:")
        with st.expander("Technical details"):
            st.code(str(exc))


# ---------------------------------------------------------------- page chrome
def header(title: str, subtitle: str):
    st.title(title)
    st.caption(subtitle)


def finding(text: str, kind: str = "risk"):
    """The one sentence a manager should leave the page with."""
    label = {"risk": ":orange-badge[:material/priority_high: Key finding]",
             "ok": ":green-badge[:material/check_circle: On track]",
             "action": ":blue-badge[:material/bolt: Recommended action]"}[kind]
    with st.container(border=True):
        st.markdown(f"{label}\n\n{text}")


def card(title: str, caption: str | None = None):
    c = st.container(border=True, height="stretch")
    c.markdown(f"**{title}**")
    if caption:
        c.caption(caption)
    return c


def target_note(value: float, target: float, unit: str = "%") -> str:
    gap = value - target
    return f"Target {target:g}{unit} · {'met' if gap >= 0 else f'{gap:+.1f} pts to go'}"


def money(v: float) -> str:
    if v is None or pd.isna(v):
        return "n/a"
    v = float(v)
    if abs(v) >= 1e9:
        return f"${v / 1e9:,.2f}B"
    if abs(v) >= 1e6:
        return f"${v / 1e6:,.1f}M"
    if abs(v) >= 1e3:
        return f"${v / 1e3:,.0f}K"
    return f"${v:,.0f}"


def title_case(s: pd.Series) -> pd.Series:
    return s.astype(str).str.replace("_", " ").str.title()


# ---------------------------------------------------------------- charts
def style(chart: alt.Chart, height: int = 300) -> alt.Chart:
    return (chart.properties(height=height)
            .configure_view(strokeWidth=0)
            .configure_axis(labelColor="#5E7183", titleColor="#5E7183", gridColor="#EDF2F6",
                            domainColor="#D0E8F2", tickColor="#D0E8F2", labelFontSize=11, titleFontSize=11,
                            titleFontWeight=500)
            .configure_legend(orient="top", title=None, labelColor="#11567F", labelFontSize=12,
                              symbolType="circle")
            .configure_point(size=45))


def rule(y: float, color: str = GREY, label: str | None = None) -> alt.LayerChart | alt.Chart:
    df = pd.DataFrame({"y": [y], "label": [label or ""]})
    line = alt.Chart(df).mark_rule(strokeDash=[5, 4], color=color, strokeWidth=1.5).encode(y="y:Q")
    if not label:
        return line
    text = alt.Chart(df).mark_text(align="left", dx=4, dy=-7, color=color, fontSize=11, fontWeight=500).encode(
        y="y:Q", text="label:N", x=alt.value(0))
    return line + text
