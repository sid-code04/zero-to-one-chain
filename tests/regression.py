"""All pages standalone and through the sidebar menu, plus simulator and sidebar layout checks."""
exec(open("/workspace/tests/harness.py").read())
print("streamlit", st.__version__)
for p in PAGES: check(p)
at = new("streamlit_app.py"); at.run()
print("entrypoint errors:", errors(at) or "none")
sb = at.sidebar
order = [type(e).__name__ + ":" + (getattr(e, "value", None) or getattr(e, "label", "") or "")[:28] for e in sb]
first_link = next(i for i, e in enumerate(sb) if type(e).__name__ == "PageLink" or "page_link" in str(getattr(e, "proto", ""))[:0]) if False else None
labels = [str(getattr(e, "value", "") or getattr(e, "label", "")) for e in sb]
def idx(text): return next((i for i, l in enumerate(labels) if text in l), -1)
print("sidebar order -> brand:", idx("Zero to One Chain"), "persona:", idx("Planning"), "status:", idx("**Project**"),
      "menu 'Command center':", idx("Command center"), "menu 'Operations':", idx("Operations"), "refresh:", idx("Refresh data"))
bad = []
for p in PAGES:
    at.switch_page(f"app_pages/{p}.py").run()
    if errors(at): bad.append((p, errors(at)[:1]))
print("navigation errors:", bad or "none")
w = new("app_pages/what_if.py"); w.run()
for wk in (1, 4): w.slider[0].set_value(wk).run(); print(f"  what-if {wk}wk:", [(m.label, m.value) for m in w.metric][2:], "errors", len(errors(w)))
