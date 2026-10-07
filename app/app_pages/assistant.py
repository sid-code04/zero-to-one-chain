import time

import streamlit as st

import agent
import ui

ui.header("Ask the Twin", "One assistant for the whole project: governed metrics, contracts, how it is built and what is happening now")

MAX_QUESTIONS = 15
STARTERS = [
    ("Explain the whole project", "Explain this project end to end in plain English", ":material/hub:"),
    ("Are we hitting delivery targets?", "What is our OTD and OTIF, and are we meeting target?", ":material/local_shipping:"),
    ("Why did APAC slip in Q3?", "Why did APAC on-time delivery drop in Q3?", ":material/query_stats:"),
    ("Who is hit if a supplier fails?", "If supplier V-000361 goes down, which customers are at risk?", ":material/science:"),
    ("What is waiting for approval?", "What is the status of the release train and what is waiting for approval?", ":material/task_alt:"),
    ("How is the data governed?", "What data governance controls are in place and how do you guarantee every team sees the same number?",
     ":material/verified_user:"),
]


def show(res: dict, key: str):
    for part in res["parts"]:
        if part[0] == "text":
            st.markdown(part[1])
        elif part[0] == "table":
            if part[2]:
                st.caption(part[2])
            st.dataframe(part[1], hide_index=True, width="stretch")
        elif part[0] == "chart":
            try:
                if "width" in ui._params(st.vega_lite_chart):
                    st.vega_lite_chart(spec=part[1], width="stretch")
                else:
                    st.vega_lite_chart(spec=part[1], use_container_width=True)
            except Exception:  # noqa: BLE001
                st.caption("Chart could not be drawn; the table above has the same data.")
    meta = []
    for t in res["tools"]:
        label, icon = agent.TOOL_LABELS[t]
        meta.append(f":gray-badge[{icon} {label}]")
    if meta:
        st.markdown(" ".join(meta))
    if res["sql"]:
        with st.expander("How this was calculated (SQL)", icon=":material/code:"):
            for s in res["sql"]:
                st.code(s, language="sql")
    if res["sources"]:
        with st.expander(f"Sources ({len(res['sources'])})", icon=":material/menu_book:"):
            for s in res["sources"]:
                kind = "Project guide" if s["tool"] == "project_guide" else "Document"
                st.markdown(f"**{s['title']}**  \n:gray[{kind}]  \n{s['text']}")
    for w in res["warnings"]:
        st.caption(f":material/warning: {w}")


def follow_ups(res: dict, i: int):
    """Suggested next questions under the latest answer; returns the one clicked."""
    clicked = None
    if res["suggestions"]:
        st.caption("Ask next")
        for j, s in enumerate(res["suggestions"]):
            if st.button(s, key=f"next_{i}_{j}", icon=":material/subdirectory_arrow_right:"):
                clicked = s
    return clicked


def render():
    chat = st.session_state.setdefault("chat", [])
    asked = sum(1 for m in chat if m["role"] == "user")
    pending = st.session_state.pop("chat_pending", None)

    intro = st.empty()
    if not chat:
        with intro.container():
            with st.container(border=True):
                st.markdown("**Ask anything about this project.** I read the same governed metric definitions as every "
                            "page in this app, so my numbers always match. I can also search 200 contracts and policies, "
                            "explain how the platform is built, and report what is happening in it right now.")
                st.caption("I am read-only: I cannot approve, release or change anything.")
            cols = st.columns(3)
            for i, (label, question, icon) in enumerate(STARTERS):
                if cols[i % 3].button(label, icon=icon, key=f"starter_{i}", width="stretch"):
                    pending = question

    for i, m in enumerate(chat):
        with st.chat_message(m["role"], avatar=None if m["role"] == "user" else ":material/smart_toy:"):
            if m["role"] == "user":
                st.markdown(m["text"])
            elif m.get("error"):
                st.warning(m["error"], icon=":material/error:")
            else:
                show(m["res"], f"m{i}")
                if i == len(chat) - 1:
                    pending = follow_ups(m["res"], i) or pending

    typed = st.chat_input("Ask about delivery, suppliers, contracts, governance or how this works", max_chars=500,
                          disabled=asked >= MAX_QUESTIONS)
    question = (typed or pending or "").strip()
    if asked >= MAX_QUESTIONS:
        st.info(f"This session reached its limit of {MAX_QUESTIONS} questions. Use **Start over** to continue.",
                icon=":material/info:")
    left, right = st.columns([5, 2], vertical_alignment="center")
    left.caption(f"{asked} of {MAX_QUESTIONS} questions used in this session · answers may take 20 to 60 seconds")
    if chat and right.button("Start over", icon=":material/restart_alt:", width="stretch"):
        st.session_state.chat = []
        st.rerun()

    if question and asked < MAX_QUESTIONS:
        intro.empty()
        history = [{"role": m["role"], "text": m["text"] if m["role"] == "user" else m.get("summary", "")} for m in chat]
        chat.append({"role": "user", "text": question})
        with st.chat_message("user"):
            st.markdown(question)
        with st.chat_message("assistant", avatar=":material/smart_toy:"):
            t0 = time.time()
            try:
                with st.spinner("Checking the governed metrics, documents and project state"):
                    res = agent.ask(history, question)
            except Exception as exc:  # noqa: BLE001
                chat.append({"role": "assistant", "error": "The assistant is unavailable right now. Please try again in a moment."})
                st.warning(chat[-1]["error"], icon=":material/error:")
                with st.expander("Technical details"):
                    st.code(str(exc))
                return
            if res["error"]:
                chat.append({"role": "assistant", "error": res["error"]})
                st.warning(res["error"], icon=":material/error:")
                return
            summary = "\n\n".join(p[1] for p in res["parts"] if p[0] == "text")
            chat.append({"role": "assistant", "res": res, "summary": summary})
            show(res, "new")
            st.caption(f"Answered in {time.time() - t0:.0f}s")
            follow_ups(res, len(chat) - 1)


ui.safe(render)
