exec(open(os.path.expanduser("~/ws/tests/harness.py")).read()) if False else None
import os; exec(open(os.path.expanduser("~/ws/tests/harness.py")).read())
import ui
print("READ_ONLY =", ui.READ_ONLY, "| streamlit", st.__version__)
bad = []
for p in PAGES:
    at = new(f"app_pages/{p}.py"); at.run()
    btns = [b.label or b.key for b in at.button]
    if errors(at): bad.append((p, errors(at)[:1]))
    print(f"{p:16} errors={len(errors(at))} buttons={btns}")
at = new("streamlit_app.py"); at.run()
print("entrypoint errors:", errors(at) or "none", "| sidebar buttons:", [b.label for b in at.sidebar.button],
      "| caption:", [str(e.value) for e in at.sidebar if "edition" in str(getattr(e, "value", "")) or "Environment" in str(getattr(e, "value", ""))])
try:
    ui.run("SELECT 1"); print("ui.run: ALLOWED")
except PermissionError as e:
    print("ui.run: refused ->", e)
