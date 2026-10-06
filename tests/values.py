import os; exec(open(os.path.expanduser("~/ws/tests/harness.py")).read())
out = {}
for p in ("command_center", "inventory", "suppliers", "actions"):
    at = new(f"app_pages/{p}.py"); at.run()
    out[p] = [(m.label, m.value) for m in at.metric][:4]
print(out)
