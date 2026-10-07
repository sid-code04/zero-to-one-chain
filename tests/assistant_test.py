"""Ask the Twin: starter, typed question, follow-up with history, limit. Run with TEST_ROLE=Z21_APP_OWNER."""
import time
exec(open("/workspace/tests/harness.py").read())
print("streamlit", st.__version__, "role", CFG["role"])
at = new("app_pages/assistant.py"); at.run()
print("initial errors:", errors(at) or "none", "| starter buttons:", len([b for b in at.button if b.key and b.key.startswith("starter_")]))

t = time.time()
at.chat_input[0].set_value("What is our OTD and OTIF, and are we meeting target?").run()
print(f"typed question {time.time()-t:.0f}s errors:", errors(at) or "none", "warnings:", [w.value[:100] for w in at.warning])
print("chat messages:", [(m.name, (m.markdown[0].value[:90] if m.markdown else "")) for m in at.chat_message])
chat = at.session_state["chat"]
res = chat[-1].get("res") or {}
print("tools:", res.get("tools"), "| sql blocks:", len(res.get("sql", [])), "| suggestions:", res.get("suggestions"), "| parts:", [p[0] for p in res.get("parts", [])])

t = time.time()
at.chat_input[0].set_value("And which region is worst?").run()
print(f"follow-up {time.time()-t:.0f}s errors:", errors(at) or "none")
print("follow-up answer:", chat[-1].get("summary", chat[-1].get("error"))[:300] if len(at.session_state['chat']) else None)
print("questions asked:", sum(1 for m in at.session_state["chat"] if m["role"] == "user"))
