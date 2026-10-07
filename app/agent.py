"""Client for the SUPPLY_CHAIN_TWIN Cortex Agent: one SQL call, parsed into things the chat page can render."""
import json

import pandas as pd
import streamlit as st

import ui
from ui import DB

AGENT = f"{DB}.L7_INTELLIGENCE.SUPPLY_CHAIN_TWIN"
TOOL_LABELS = {
    "supply_chain_analyst": ("Governed metrics", ":material/analytics:"),
    "document_search": ("Contracts & policies", ":material/description:"),
    "project_guide": ("Project guide", ":material/menu_book:"),
    "project_status": ("Live project status", ":material/monitor_heart:"),
}
SEARCH_TOOLS = ("document_search", "project_guide")
MAX_HISTORY = 6
MAX_TEXT = 1500


def _body(history: list[dict], question: str) -> str:
    msgs = [{"role": m["role"], "content": [{"type": "text", "text": m["text"][:MAX_TEXT]}]}
            for m in history[-MAX_HISTORY:] if m.get("text")]
    msgs.append({"role": "user", "content": [{"type": "text", "text": question}]})
    return json.dumps({"messages": msgs})


@st.cache_data(ttl=300, show_spinner=False, max_entries=64)
def _run(body: str) -> str:
    """Identical conversations within five minutes reuse the answer, so repeats are instant and free."""
    return ui.conn().session().sql("SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?)", params=[AGENT, body]).collect()[0][0]


def _table(item: dict) -> pd.DataFrame | None:
    rs = (item.get("table") or {}).get("result_set") or {}
    cols = [c["name"] for c in rs.get("resultSetMetaData", {}).get("rowType", [])]
    if not cols:
        return None
    df = pd.DataFrame(rs.get("data", []), columns=cols)
    for c in df.columns:
        try:
            df[c] = pd.to_numeric(df[c])
        except (ValueError, TypeError):
            pass
    return df


def ask(history: list[dict], question: str) -> dict:
    """Returns {parts, sql, sources, tools, suggestions, warnings, error}."""
    out = {"parts": [], "sql": [], "sources": [], "tools": [], "suggestions": [], "warnings": [], "error": None}
    raw = _run(_body(history, question))
    try:
        resp = json.loads(raw)
    except (TypeError, ValueError):
        out["error"] = "The assistant returned an unreadable response."
        return out
    content = resp.get("content")
    if not content:
        out["error"] = resp.get("message") or "The assistant returned no answer."
        return out
    out["warnings"] = [w.get("message", "") for w in resp.get("warnings") or []]

    last_tool = max((i for i, c in enumerate(content) if c.get("type") in ("tool_use", "tool_result", "thinking")),
                    default=-1)
    seen = set()
    for i, c in enumerate(content):
        kind = c.get("type")
        if kind == "tool_use":
            tu = c.get("tool_use", {})
            if tu.get("name") == "system_execute_sql" and tu.get("input", {}).get("sql"):
                out["sql"].append(tu["input"]["sql"].strip())
            elif tu.get("name") in TOOL_LABELS and tu["name"] not in out["tools"]:
                out["tools"].append(tu["name"])
        elif kind == "tool_result":
            tr = c.get("tool_result", {})
            if tr.get("name") == "supply_chain_analyst" and "supply_chain_analyst" not in out["tools"]:
                out["tools"].append("supply_chain_analyst")
            if tr.get("name") in SEARCH_TOOLS:
                for blk in tr.get("content", []):
                    for r in blk.get("json", {}).get("search_results", []):
                        key = (tr["name"], r.get("doc_title"))
                        if r.get("doc_title") and key not in seen:
                            seen.add(key)
                            out["sources"].append({"tool": tr["name"], "title": r["doc_title"],
                                                   "text": (r.get("text") or "")[:600]})
        elif kind == "suggested_queries":
            out["suggestions"] = [q["query"] for q in c.get("suggested_queries", []) if q.get("query")][:3]
        elif i > last_tool:
            if kind == "text" and (c.get("text") or "").strip():
                out["parts"].append(("text", c["text"].strip()))
            elif kind == "table":
                df = _table(c)
                if df is not None and len(df):
                    out["parts"].append(("table", df, c.get("table", {}).get("title")))
            elif kind == "chart":
                try:
                    spec = json.loads(c["chart"]["chart_spec"])
                    spec.pop("width", None)
                    out["parts"].append(("chart", spec))
                except (KeyError, TypeError, ValueError):
                    pass
    if not out["parts"]:
        texts = [c.get("text", "").strip() for c in content if c.get("type") == "text" and c.get("text", "").strip()]
        if texts:
            out["parts"].append(("text", texts[-1]))
        else:
            out["error"] = "The assistant could not produce an answer for that. Try rephrasing the question."
    return out
