# Hub Companion — demo pack

Everything for the 8 Aug demo. All content is fictional.

| File | What it is |
|---|---|
| `hub-companion-prd-v0.3.md` | Full PRD as built — ten screens, Kea, languages, tiers, run sheet, open questions, licences |
| `demo-seed-data-v0.3.json` | Complete mock dataset: the v0.2 scenario plus tasks with WREMO references, multi-person roster, monitor feeds, Kea corpus, five-language strings, export config |
| `../Hub Companion Demo.dc.html` | The working console — open it in a browser, no install |

## The console at a glance

Ten tabs: My shift · Situation · Needs & offers · Roles, roster & tasks · Live monitor · Status report · Public info · Am I impacted? · Ask Kea · Records · Settings.

Kea sits in the bottom-right corner of every screen.

## Demo controls

- **Role picker** (header) — changes whose runbook, jobs and contacts you see. Contacts are visible only to Needs and Offers and the Supervisor.
- **Language** (header) — English · Te Reo Māori · Gagana Sāmoa · 简体中文 · हिन्दी.
- **Simulate offline** (header) — drops the basemap, marks every feed cached, forces Kea on-device, shows the stale-data banner.
- **Settings tab** — every feed with its endpoint and licence, the four export channels, the redaction table, Kea's model connection with a live test, and the EOC API token.

## Run sheet (~4 minutes)

1. **0:00** Framing: 127 community hubs, paper boards, a VHF radio. Hub Guide page beside the screen.
2. **0:20** My shift as Marcus (Needs and Offers) — runbook, jobs urgent-first, each with how / when / where and a WREMO page to check against.
3. **1:00** Needs & offers — Kea's suggested matches; read the wheelchair caveat aloud; confirm a match with an outcome note.
4. **1:40** NEED-001 — life-threatening hard route, sharing refused, already in the EOC queue.
5. **2:10** Ask Kea — guide answer with a page; "latest quakes" feed answer with attribution; the evacuation question gets the fixed refusal; turn an answer into a task and assign it.
6. **2:50** Status report — compiles live, radio script, print A4.
7. **3:20** Simulate offline — everything keeps working, honestly labelled.
8. **3:40** Switch to 简体中文 — chrome and the natural-warning rule translate, the untranslated note appears.
9. **3:50** Ask: test it in a WREMO hub practice exercise.

## Before anyone relies on this

- Every translation is machine-drafted and needs native-speaker review; te reo Māori needs WREMO and mana whenua engagement.
- Every WREMO page reference in the tasks and Kea corpus must be checked against the printed July 2025 guide.
- Checker zone classes are demo placeholders — verify against the live WCC layer before seeding real points.
- The hubs layer is CC BY-NC-ND 4.0: demo with attribution is fine, launch needs permission or an independent dataset.
