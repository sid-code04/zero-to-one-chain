# Zero to One Chain — Supply Chain Decision Twin

> **One question. One answer. One decision.**
> A governed supply chain ontology and decision twin built natively on Snowflake with **Snowflake CoCo CLI**.

Built for the **Snowflake CoCo CLI Hackathon — GCC Edition**
Problem Statement: **Supply Chain Ontology and Governed Conversational Analytics**

---

## The Problem

Supply chain data is scattered across ERP, logistics (TMS), supplier (SRM), and IoT systems — each with its own definitions. Ask *"What is our on-time delivery?"* and Planning, Procurement, and Logistics each get a different number.

The root problem is not a lack of AI. It is **semantic inconsistency**. AI on top of inconsistent definitions just produces confident wrong answers faster.

## Our Solution

**Zero to One Chain** fixes meaning first, then layers intelligence and action on top:

1. **Consistent** — one governed definition per metric; every persona gets the identical answer.
2. **Explain** — root cause by traversing the ontology graph (*why did OTD drop in the West?*).
3. **Impact** — propagate a disruption through the network (*if Supplier X slips 2 weeks, which customers and how much revenue are at risk?*).
4. **Act** — recommend a mitigation with cost/service trade-offs, gated by human approval and fully audited.

---

## Architecture — 9 Layers

```
┌──────────────────────────────────────────────────────────────┐
│ L9  EXPERIENCE       Streamlit Command Center · Dashboards   │
│ L8  ACTION           Recommendations · Approvals · Audit     │
│ L7  INTELLIGENCE     Cortex Agent · Analyst · Search · ML    │
│ L6  SEMANTIC         Ontology → Semantic Views → Metrics     │
│ L5  CURATED CORE     Conformed entities · Graph · History    │
│ L4  HARMONIZE / MDM  Entity resolution · Golden records      │
│ L3  VALIDATE         DQ rules · Quarantine · Reconciliation  │
│ L2  STAGE            Typing · Standardize · Dedup · CDC      │
│ L1  INGESTION        Raw ERP · TMS · SRM · IoT · Documents   │
└──────────────────────────────────────────────────────────────┘
   ⟂ CROSS-CUTTING: Governance · Data Quality · Lineage · Reliability
```

| Layer | Purpose | Snowflake Features |
|---|---|---|
| **L1 Ingestion** | Land raw data from 4 source systems with deliberately conflicting definitions, plus unstructured contracts/SLAs/incidents | Tables, Stages, Dynamic Tables |
| **L2 Stage** | Typing, unit/currency/timezone normalization, dedup, incremental CDC, document parsing | Streams, Dynamic Tables, `AI_PARSE_DOCUMENT` |
| **L3 Validate** | Completeness, freshness, range and referential checks; quarantine with reasons; cross-source reconciliation; circuit breaker | Data Metric Functions, Tasks |
| **L4 Harmonize / MDM** | Entity resolution across sources, golden records with confidence, definition crosswalk, survivorship rules | `AI_SIMILARITY`, SQL |
| **L5 Curated Core** | Conformed entities, hierarchies, ontology edge table, SCD2 history | Tables, Dynamic Tables |
| **L6 Semantic** | Ontology encoded as governed semantic views with canonical metrics, synonyms, verified queries | Semantic Views, Cortex Analyst |
| **L7 Intelligence** | Agent orchestrating metrics, evidence search, root cause, impact propagation, what-if; forecasting & anomaly detection | Cortex Agent, Cortex Search, Snowflake ML |
| **L8 Action** | Recommendations, AI-drafted decision memos with citations, human approval, decision audit trail, proactive alerts | `AI_COMPLETE`, Tables, Alerts, Tasks |
| **L9 Experience** | Command center app and dashboards | Streamlit in Snowflake, Snowsight Dashboards |

---

## The Ontology

```
Supplier ──supplies──▶ Part ──used_at──▶ Plant ──ships──▶ Shipment ──fulfills──▶ Order ──placed_by──▶ Customer
```

**Hierarchies:** Part → Category → Family · Plant → Region → Country · Day → Week → Month → Quarter

### Canonical Metrics (defined once, used everywhere)

| Metric | Definition |
|---|---|
| **On-Time Delivery (OTD)** | % of order lines delivered on or before the committed date |
| **OTIF** | % of order lines delivered on time *and* in full |
| **Fill Rate** | Quantity shipped ÷ quantity ordered |
| **Days of Inventory (DOI)** | On-hand inventory value ÷ average daily COGS |
| **Landed Cost** | Unit cost + freight + duty + handling |
| **Supplier Risk Score** | Weighted blend of OTD trend, lead-time variance, SLA breaches, concentration |

---

## Personas & Governance

| Persona | Role | Sees |
|---|---|---|
| Planning | `Z21_PLANNER` | Demand, inventory, OTD/OTIF, all regions |
| Procurement | `Z21_PROCUREMENT` | Suppliers, landed cost (unmasked), risk |
| Logistics | `Z21_LOGISTICS` | Shipments, carriers, region-scoped rows |

- Masking policies on supplier cost
- Row access policies by region
- Lineage from every answer back to source
- **Same metric → identical result across all three personas** (proven in the Consistency dashboard)

---

## Application & Dashboards

**Streamlit Command Center**
- Persona switcher
- Conversational chat with evidence, generated SQL, and metric definitions
- Supply network map with disruption highlighting
- What-if simulator
- Approval queue for agent recommendations
- Agent evaluation scores

**Dashboards:** Executive KPIs · Consistency · Supplier Risk · Disruption Impact · Trust & Governance

---

## Repository Structure

```
zero-to-one-chain/
├── sql/
│   ├── 00_preflight.sql        # feature, role, region checks
│   ├── 01_setup.sql            # database, schemas, warehouse, roles
│   ├── L1_ingestion/
│   ├── L2_stage/
│   ├── L3_validate/
│   ├── L4_harmonize/
│   ├── L5_core/
│   ├── L6_semantic/
│   ├── L7_intelligence/
│   ├── L8_action/
│   ├── governance/
│   ├── 98_healthcheck.sql
│   └── 99_teardown.sql
├── semantic/                   # semantic view definitions
├── agent/                      # Cortex Agent spec + evaluation set
├── app/                        # Streamlit command center
├── data/                       # synthetic data generators + sample documents
├── docs/                       # architecture diagrams, demo script
└── README.md
```

---

## Getting Started

**Prerequisites:** Snowflake account with Cortex AI features enabled, a role able to create databases/roles/integrations, and a warehouse.

```sql
-- 1. Check environment readiness
!source sql/00_preflight.sql

-- 2. Build everything (idempotent — safe to re-run)
!source sql/01_setup.sql
-- then run each layer folder in order: L1 → L8, governance

-- 3. Verify
!source sql/98_healthcheck.sql
```

Full rebuild target: **~10 minutes from an empty account**.

---

## Reliability

- **Preflight** validates role, warehouse, Cortex availability, and region before build
- **Idempotent scripts** — rebuild in any account
- **Deterministic synthetic data** — demo anomalies always reproduce
- **Graceful degradation** — if Cortex Search is unavailable, the agent falls back to structured answers
- **Eval gate** — demo questions must pass before release
- **Cost guardrails** — auto-suspend warehouse and resource monitor

---

## Data

All data is **fully synthetic**. No real customer, supplier, or personal data is used.

---

## Roadmap

- [ ] L1 Ingestion — synthetic multi-source data + documents
- [ ] L2 Stage
- [ ] L3 Validate
- [ ] L4 Harmonize / MDM
- [ ] L5 Curated Core + ontology graph
- [ ] L6 Semantic views + canonical metrics
- [ ] L7 Cortex Agent, Search, ML
- [ ] L8 Recommendations, approvals, audit
- [ ] Governance — roles, masking, row access, lineage
- [ ] L9 Streamlit command center + dashboards
- [ ] Evaluation suite + demo script

---

## Team

**Zero to One Chain**

> *"Most supply chain tools improve what exists. We take supply chain truth from zero to one."*

Built with Snowflake CoCo CLI.
