# Zero to One Chain: submission text

## Challenge (dropdown)
Supply Chain Ontology & Governed Conversational Analytics

## Prototype/MVP Brief (paste into the form, about 1,350 characters)

Zero to One Chain is a Supply Chain Decision Twin built entirely in Snowflake with Cortex Code. It turns 544K raw ERP, TMS, SRM and IoT rows (11 source tables) into one governed truth that every team, dashboard and AI agent shares. A 9-layer architecture runs from ingestion through a DQ quarantine and circuit breaker, dbt models (41/41 tests passing), Dynamic Tables, an ontology linking suppliers, parts, plants, customers and orders, and a semantic view with canonical metrics (OTD, OTIF, fill rate, days of inventory). A Cortex Agent answers plain-English questions with Cortex Analyst (24 verified queries) and Cortex Search over 200 contracts and SOPs. A consistency proof shows all 6 metrics are identical for Planning, Procurement and Logistics. Masking, row access, tags and data metric functions enforce governance in Snowflake. The Streamlit app explains what changed (APAC ocean on-time fell from 90.5% to 55.8%), simulates supplier outages, and routes data-driven recommendations to human approval with a full audit trail. DEV, UAT and PROD are separate databases: a release train detects DEV changes, releases and verifies UAT automatically, and sends PROD only after human approval.

## 3-minute demo video script (input -> processing -> output)

0:00-0:15  Problem
"Planning, Procurement and Logistics get different answers to the same question. Zero to One Chain gives them one governed truth, and turns it into approved action."

0:15-0:40  INPUT
Show Snowsight: database ZERO_TO_ONE_CHAIN, schema L1_INGESTION (11 tables, 544K rows). Then the dbt project: 41 of 41 tests passing.

0:40-1:05  PROCESSING
App > Operations: the hourly task graph (DQ refresh > circuit breaker > consistency + anomaly scan > log > release train). App > Trust & quality: quarantine, quality gate open, consistency proof 6 of 6 identical.

1:05-1:45  OUTPUT, insight
App > Command center: on-time delivery 88.7% in Q3, down 5.4 pts. Finding: APAC alone explains the drop.
App > Delivery: APAC ocean fell from 90.5% to 55.8%. All 8 APAC Platinum and Gold customers are below 90%, with $15.9M delivered late. No other region is affected.
Ask the Cortex Agent: "Why did APAC on-time delivery drop in Q3?" It gives the same answer, from governed SQL.

1:45-2:15  DECIDE
App > Disruption simulator: pick a top supplier and slide the outage from 1 to 4 weeks: 4 customers become 9, and $255K at risk becomes $677K.

2:15-2:45  ACT
App > Action queue: approve a recommendation with a note. Show it in the audit trail (name, role, note).
Then the release train: release #5 shows "UAT verified, awaiting approval". Click Review release > Approve. The approval checks DEV still matches the verified build, then releases to PROD.

2:45-3:00  Close
App > Operations: DEV, UAT and PROD show identical metrics. Stop project switches all three off. "One governed truth, from raw row to approved action."

Recording tips: record in 1080p; stop at 2:55; the PROD release takes about 5 minutes, so click Approve, cut the video, and resume when the panel shows "In PROD".
