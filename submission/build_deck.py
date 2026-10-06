"""Builds the hackathon prototype deck (PDF, 16:9) from verified project facts.

Usage: python3 build_deck.py "<team leader name>" "<team size>"
"""
import sys

from reportlab.lib.colors import HexColor, white
from reportlab.pdfgen import canvas

LEADER = sys.argv[1] if len(sys.argv) > 1 else "[Team leader]"
SIZE = sys.argv[2] if len(sys.argv) > 2 else "[Team size]"
OUT = "/workspace/submission/Zero_to_One_Chain_Prototype_Deck.pdf"

W, H = 960, 540
NAVY, BLUE, ORANGE, GREEN, RED = HexColor("#11567F"), HexColor("#29B5E8"), HexColor("#FF8B00"), HexColor("#36B37E"), HexColor("#DE350B")
INK, MUTED, PALE, LINE = HexColor("#1B2B3A"), HexColor("#5E7183"), HexColor("#F4F9FC"), HexColor("#D0E8F2")

c = canvas.Canvas(OUT, pagesize=(W, H))
c.setTitle("Zero to One Chain - Supply Chain Decision Twin")
c.setAuthor("Team Zero to One Chain")
page_no = [0]


def text(x, y, s, size=12, color=INK, font="Helvetica", anchor="left"):
    c.setFillColor(color); c.setFont(font, size)
    {"left": c.drawString, "center": c.drawCentredString, "right": c.drawRightString}[anchor](x, y, s)


def wrap(x, y, s, width, size=11, color=INK, font="Helvetica", leading=None):
    """Draw wrapped text; returns the y below the last line."""
    leading = leading or size * 1.35
    c.setFillColor(color); c.setFont(font, size)
    line = ""
    for word in s.split():
        trial = f"{line} {word}".strip()
        if c.stringWidth(trial, font, size) > width:
            c.drawString(x, y, line); y -= leading; line = word
        else:
            line = trial
    if line:
        c.drawString(x, y, line); y -= leading
    return y


def box(x, y, w, h, fill=PALE, stroke=LINE, r=8):
    c.setFillColor(fill); c.setLineWidth(1)
    if stroke:
        c.setStrokeColor(stroke)
    c.roundRect(x, y, w, h, r, fill=1, stroke=1 if stroke else 0)


def bullets(x, y, items, width, size=11, gap=6, color=INK, dot=BLUE):
    for it in items:
        c.setFillColor(dot); c.circle(x + 3, y + size * 0.35, 2.4, fill=1, stroke=0)
        y = wrap(x + 12, y, it, width - 12, size, color) - gap
    return y


def page(title, kicker=None):
    if page_no[0]:
        c.showPage()
    page_no[0] += 1
    c.setFillColor(white); c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(NAVY); c.rect(0, H - 6, W, 6, fill=1, stroke=0)
    if kicker:
        text(48, H - 44, kicker.upper(), 10, BLUE, "Helvetica-Bold")
    text(48, H - 74, title, 24, NAVY, "Helvetica-Bold")
    c.setStrokeColor(LINE); c.line(48, 34, W - 48, 34)
    text(48, 18, "Zero to One Chain  ·  Snowflake CoCo CLI Hackathon, GCC Edition", 9, MUTED)
    text(W - 48, 18, str(page_no[0]), 9, MUTED, anchor="right")


def stat(x, y, w, value, label, color=NAVY):
    box(x, y, w, 70, white)
    text(x + 14, y + 38, value, 22, color, "Helvetica-Bold")
    wrap(x + 14, y + 18, label, w - 24, 9.5, MUTED)


# 1 ---------------------------------------------------------------- title + template fields
page_no[0] += 1
c.setFillColor(NAVY); c.rect(0, 0, W, H, fill=1, stroke=0)
c.setFillColor(BLUE); c.rect(0, 0, 10, H, fill=1, stroke=0)
text(60, 440, "SNOWFLAKE COCO CLI HACKATHON  ·  GCC EDITION", 11, BLUE, "Helvetica-Bold")
text(60, 392, "Zero to One Chain", 44, white, "Helvetica-Bold")
text(60, 358, "Supply Chain Decision Twin: one governed truth, from raw ERP rows to an approved action", 15, HexColor("#CFE9F7"))
fields = [("Team Name", "Zero to One Chain"), ("Team Leader Name", LEADER), ("Team Size", SIZE),
          ("Problem Statement", "Supply Chain Ontology & Governed Conversational Analytics")]
y = 280
for k, v in fields:
    text(60, y, k, 11, HexColor("#9CC9E3"), "Helvetica-Bold")
    text(230, y, v, 14, white, "Helvetica-Bold")
    y -= 34
text(60, 60, "Built end to end in Snowflake with Cortex Code (CoCo): dbt, Dynamic Tables, Tasks, Semantic View,", 11, HexColor("#CFE9F7"))
text(60, 44, "Cortex Analyst, Cortex Search, Cortex Agents, Snowflake ML, Horizon governance, Streamlit", 11, HexColor("#CFE9F7"))

# 2 ---------------------------------------------------------------- problem
page("Same question, three different answers", "The problem")
wrap(48, 430, "Supply chain data lives in separate systems (ERP, TMS, SRM, IoT). Each team rebuilds its own logic, "
     "so Planning, Procurement and Logistics argue about whose number is right instead of acting on it.",
     560, 13, INK, leading=19)
pains = [
    ("Conflicting definitions", "\"On-time\" means delivered lines to one team and all lines to another, so OTD differs by team."),
    ("No connected view", "Nobody can trace supplier → part → customer order, so a supplier outage is noticed only when customers complain."),
    ("Answers nobody trusts", "Chat-based BI hallucinates metrics; dirty source rows silently flow into dashboards."),
    ("Insight without action", "Dashboards stop at a chart; decisions and approvals happen in email with no audit trail."),
]
y = 340
for i, (h, d) in enumerate(pains):
    x = 48 + (i % 2) * 300; yy = y - (i // 2) * 130
    box(x, yy - 70, 285, 110)
    text(x + 16, yy + 18, h, 13, NAVY, "Helvetica-Bold")
    wrap(x + 16, yy - 4, d, 255, 10.5, MUTED)
box(668, 90, 244, 340, NAVY, None)
text(688, 398, "WHAT JUDGES CAN VERIFY", 9.5, BLUE, "Helvetica-Bold")
for j, (v, l) in enumerate([("544K", "raw rows across 11 source tables (22-38 columns each)"),
                            ("6 / 6", "canonical metrics identical for all three personas"),
                            ("3", "fully separate environments: DEV, UAT, PROD"),
                            ("0", "manual steps from a DEV change to a verified UAT build")]):
    yy = 350 - j * 72
    text(688, yy, v, 26, white, "Helvetica-Bold")
    wrap(688, yy - 18, l, 205, 10, HexColor("#CFE9F7"))

# 3 ---------------------------------------------------------------- solution
page("A decision twin: ontology, governed semantics, agents, action", "Our solution")
cols = [
    ("1  Connect", BLUE, "Ontology of suppliers, parts, plants, customers, orders and shipments, with entity resolution across ERP and SRM supplier records."),
    ("2  Govern", NAVY, "One semantic view holds canonical metrics (OTD, OTIF, fill rate, landed cost, days of inventory). Masking, row access, tags and data metric functions are enforced in Snowflake."),
    ("3  Ask", ORANGE, "A Cortex Agent answers in plain English with Cortex Analyst (24 verified queries) plus Cortex Search over 200 contracts and SOPs, always on governed definitions."),
    ("4  Act", GREEN, "Disruption simulator, data-driven recommendations, human approval and an audit trail. Delivered through a release train from DEV to UAT to PROD."),
]
for i, (h, col, d) in enumerate(cols):
    x = 48 + i * 218
    box(x, 236, 205, 184, white)
    c.setFillColor(col); c.rect(x, 412, 205, 8, fill=1, stroke=0)
    text(x + 16, 380, h, 16, col, "Helvetica-Bold")
    wrap(x + 16, 352, d, 175, 11, INK, leading=16)
wrap(48, 200, "Result: every persona, dashboard and agent reads the same governed definition, and every recommended action "
     "is traceable from the raw row that triggered it to the person who approved it.", 864, 12, NAVY, "Helvetica-Bold")

# 4 ---------------------------------------------------------------- architecture
page("9-layer architecture, all native Snowflake", "Architecture")
layers = [
    ("L1 Ingestion", "11 raw source tables, 544K rows", BLUE),
    ("L2 Stage", "dbt staging views, typed and cleaned", BLUE),
    ("L3 Validate", "DQ quarantine, circuit breaker, DMFs", ORANGE),
    ("L4 Harmonize", "Dynamic Tables: entity resolution", NAVY),
    ("L5 Core", "dbt marts: facts and dimensions (41 tests)", NAVY),
    ("L6 Semantic", "Semantic view, canonical metrics, consistency proof", NAVY),
    ("L7 Intelligence", "Cortex Agent, Analyst, Search, ML forecast + anomaly", GREEN),
    ("L8 Action", "Recommendations, approvals, alerts, release train", GREEN),
    ("L9 Experience", "Streamlit decision app, 8 pages, 3 personas", GREEN),
]
for i, (n, d, col) in enumerate(layers):
    y = 418 - i * 40
    box(48, y, 560, 32, white)
    c.setFillColor(col); c.roundRect(48, y, 130, 32, 8, fill=1, stroke=0)
    text(60, y + 11, n, 11, white, "Helvetica-Bold")
    text(192, y + 11, d, 11, INK)
box(636, 58, 276, 392, NAVY, None)
text(656, 420, "CROSS-CUTTING", 9.5, BLUE, "Helvetica-Bold")
bullets(656, 392, [
    "Governance: masking and row access policies, classification tags, 3 data metric functions",
    "Orchestration: hourly task DAG with circuit breaker and 3 alerts",
    "Environments: DEV, UAT, PROD as separate databases, each built by dbt",
    "Release train: change detection, auto UAT release, verified, human-approved PROD",
    "Cost control: resource monitor, 60s auto-suspend, one-click project stop",
], 240, 10.5, 9, white, BLUE)

# 5 ---------------------------------------------------------------- workflow demo
page("One working workflow, input to output", "Demo workflow")
steps = [
    ("INPUT", BLUE, "Raw ERP, TMS and SRM rows land in L1: 100K sales orders, 100K POs, 80K shipments."),
    ("PROCESS", NAVY, "DQ quarantine and circuit breaker, then dbt build and test, Dynamic Tables, and the semantic view."),
    ("INSIGHT", ORANGE, "APAC ocean on-time fell from 90.5% to 55.8% in Q3. All 8 APAC Platinum/Gold customers are below 90%, with $15.9M delivered late."),
    ("DECIDE", RED, "Simulator: a 4-week outage at one supplier hits 9 customers and $677K. The agent explains why, using governed SQL."),
    ("ACT", GREEN, "A recommendation is approved in the Action queue: status updated and written to the audit trail with name and role."),
]
for i, (h, col, d) in enumerate(steps):
    x = 48 + i * 176
    box(x, 236, 164, 174, white)
    c.setFillColor(col); c.roundRect(x, 372, 164, 38, 8, fill=1, stroke=0)
    text(x + 82, 386, h, 13, white, "Helvetica-Bold", "center")
    wrap(x + 14, 345, d, 138, 10.5, INK, leading=15)
    if i < 4:
        c.setFillColor(MUTED); c.setFont("Helvetica-Bold", 18); c.drawCentredString(x + 170, 318, ">")
wrap(48, 204, "Every number above comes from the live app and the semantic view. The Cortex Agent returns the same "
     "figure because it generates SQL against the same governed metric (OTD = delivered lines only).", 864, 11.5, MUTED)

# 6 ---------------------------------------------------------------- governed conversational analytics
page("Conversational analytics you can trust", "Governance + AI")
left = [
    "Semantic view SUPPLY_CHAIN_ANALYTICS: 4 logical tables, canonical metrics, 24 verified queries",
    "Cortex Agent SUPPLY_CHAIN_TWIN routes between Cortex Analyst (structured) and Cortex Search (200 contracts, SOPs, incident notes)",
    "Remediation agent proposes fixes for quarantined records; a human applies them",
    "Consistency proof task re-computes each metric as Planning, Procurement and Logistics every hour: 6 of 6 identical",
]
right = [
    "Masking: supplier spend visible to Procurement only; contact emails masked for non-admin roles",
    "Row access: Logistics sees AMERICAS and EMEA customer rows only",
    "Classification tags (PII, FINANCIAL) on sensitive columns",
    "Data metric functions: negative values, out-of-range rates, orphan suppliers",
    "Quality gate: any critical issue blocks every promotion to UAT and PROD",
]
box(48, 196, 420, 234, white); text(66, 402, "Same answer for every persona", 14, NAVY, "Helvetica-Bold")
bullets(66, 374, left, 384, 11, 10)
box(492, 196, 420, 234, white); text(510, 402, "Governed in Snowflake, not in the app", 14, NAVY, "Helvetica-Bold")
bullets(510, 374, right, 384, 11, 10)

# 7 ---------------------------------------------------------------- production readiness
page("Production-ready, not a notebook demo", "Engineering")
stats = [("41 / 41", "dbt tests passing in DEV, UAT and PROD"), ("14", "Dynamic Tables keeping layers fresh"),
         ("6", "tasks in the hourly DAG, incl. release train"), ("3", "alerts: SLA breach, stockout, DQ critical")]
for i, (v, l) in enumerate(stats):
    stat(48 + i * 218, 360, 205, v, l)
box(48, 136, 864, 200, white)
text(66, 308, "Release train: DEV  >  UAT (automatic)  >  PROD (human approval)", 14, NAVY, "Helvetica-Bold")
bullets(66, 280, [
    "At the end of each hourly DEV run, a content fingerprint (HASH_AGG of every raw table plus a hash of every view, "
    "procedure, Dynamic Table, task, semantic view, search service, agent and dbt project) is compared with the last release.",
    "Unchanged: logged and skipped, so an hourly release never wastes credits. Changed: DQ gate, data promotion, dbt build "
    "and tests, full-stack deploy to UAT, then UAT is verified (metric parity with DEV, 0 critical DQ issues, consistency proof).",
    "A verified build raises a PROD approval card. Approval is refused if DEV changed after verification, so PROD only ever "
    "receives exactly what passed UAT. Newer builds supersede older approvals.",
    "One switch starts or stops the whole project across all three environments; every action is audited.",
], 826, 11, 9)

# 8 ---------------------------------------------------------------- features + why
page("Snowflake features, each chosen for a reason", "Why these features")
feats = [
    ("dbt Projects on Snowflake", "Versioned, tested transformations; the same code builds every environment"),
    ("Dynamic Tables", "Declarative freshness for harmonized layers without hand-written refresh jobs"),
    ("Tasks + Alerts", "Hourly DAG with circuit breaker; alerts raise recommendations automatically"),
    ("Semantic View", "Single home for metric definitions shared by the app, Analyst and the agent"),
    ("Cortex Analyst + Agents", "Natural-language questions answered with governed, inspectable SQL"),
    ("Cortex Search", "Grounds answers in contracts and SOPs, not only tables"),
    ("Snowflake ML", "OTD forecast and inventory anomaly detection inside the warehouse"),
    ("Horizon governance", "Masking, row access, tags and DMFs enforced at the data, for every tool"),
    ("Streamlit in Snowflake", "Decision app runs next to the data with the caller's governance"),
    ("Resource monitor", "Hard daily credit cap; the release train is change-driven to stay within it"),
]
for i, (f, why) in enumerate(feats):
    x = 48 + (i % 2) * 436; y = 410 - (i // 2) * 72
    box(x, y - 22, 424, 60, white)
    text(x + 16, y + 18, f, 12, NAVY, "Helvetica-Bold")
    wrap(x + 16, y, why, 392, 10.5, MUTED)

# 9 ---------------------------------------------------------------- impact
page("Impact", "Outcome")
for i, (v, l, col) in enumerate([("1 truth", "one governed definition per metric across app, agent and personas", NAVY),
                                 ("Minutes", "from a data change to a verified UAT build, with no manual steps", BLUE),
                                 ("Seconds", "to see which customers a supplier outage hits, before they call", ORANGE),
                                 ("100%", "of decisions and releases audited with name, role and note", GREEN)]):
    stat(48 + i * 218, 340, 205, v, l, col)
box(48, 150, 864, 160, white)
text(66, 282, "Next steps", 14, NAVY, "Helvetica-Bold")
bullets(66, 254, [
    "Connect live ERP/TMS feeds with Snowpipe Streaming or Openflow in place of the synthetic sources",
    "Add more domain models (finance, healthcare supply) on the same ontology and semantic layer",
    "Expose the agent in Snowflake Intelligence and Microsoft Teams for planners in the field",
    "Close the loop: write approved actions back to ERP purchase orders through external access",
], 826, 11.5, 10)

c.save()
print("wrote", OUT)
