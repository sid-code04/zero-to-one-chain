"""No page may show NaN/None text to a viewer."""
import re
exec(open("/workspace/tests/harness.py").read())
def texts(at):
    out = []
    for kind in ("markdown", "caption", "metric", "text", "success", "warning", "info", "error"):
        for e in getattr(at, kind, []):
            out.append(str(getattr(e, "value", "")) + " " + str(getattr(e, "label", "")) + " " + str(getattr(e, "delta", "")))
    return out
bad = []
for p in PAGES:
    at = new(f"app_pages/{p}.py"); at.run()
    hits = [t[:90] for t in texts(at) if re.search(r"\$nan|\bnan\b|\bNaN\b|\bNone\b", t)]
    errs = [e for e in errors(at) if not e.lstrip().upper().startswith(("SELECT", "WITH"))]
    print(f"{p:15s} errors={len(errs)} nan_hits={len(hits)}", hits[:2])
a = new("app_pages/actions.py"); a.run()
print("actions captions:", [c.value for c in a.caption if "estimated" in c.value.lower()])
print("actions KPI:", [(m.label, m.value) for m in a.metric][:6])
