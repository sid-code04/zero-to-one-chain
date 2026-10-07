exec(open("/workspace/tests/harness.py").read())
def real_errors(at): return [e for e in errors(at) if not e.lstrip().upper().startswith(("SELECT", "WITH"))]
at = new("streamlit_app.py"); at.run()
print("entrypoint errors:", real_errors(at) or "none")
labels = [str(getattr(e, "value", "") or getattr(e, "label", "")) for e in at.sidebar]
print("sidebar has ASK section + page:", any("ASK" in l for l in labels), any("Ask the Twin" in l for l in labels))
order = [i for i, l in enumerate(labels) if any(k in l for k in ("ASK", "PERFORMANCE", "Ask the Twin", "Command center", "**Project**", "Planning"))]
print("sidebar order sample:", [labels[i][:22] for i in order])
bad = []
for p in ["assistant"] + PAGES:
    at.switch_page(f"app_pages/{p}.py").run()
    if real_errors(at): bad.append((p, real_errors(at)[:1]))
print("navigation errors:", bad or "none")
# starter button path + no duplicate rendering
at.switch_page("app_pages/assistant.py").run()
nstart = [b for b in at.button if b.key == "starter_0"]
nstart[0].click().run()
print("starter run errors:", real_errors(at) or "none", "| chat_message count (expect 2):", len(at.chat_message))
chat = at.session_state["chat"]; r = chat[-1]
print("starter answer tools:", r.get("res", {}).get("tools"), "| sources:", len(r.get("res", {}).get("sources", [])), "| len:", len(r.get("summary", "")), "| error:", r.get("error"))
print("start over:", end=" ")
[b for b in at.button if b.label == "Start over"][0].click().run()
print(len(at.session_state["chat"]), "messages left;", "starters back:", len([b for b in at.button if b.key and b.key.startswith("starter_")]))
