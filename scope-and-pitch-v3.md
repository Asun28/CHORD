# The Aggregation Layer — Scope & Pitch **v3**
**Day 2 · 6 August 2026 · supersedes v1 and v2**

*Consolidates the Omega engineering review. Two pieces of my earlier advice are reversed here — the sovereignty default (§5) and the CRP sample size (§6). Both changes make the pitch stronger, not just more correct.*

---

## 1. The hook

> **Every one of Wellington's 127 volunteer emergency hubs has an official response plan — naming its neighbouring hubs, its water tank, its aged-care facilities. They're PDFs. Nobody opens a PDF in an earthquake.**
>
> **We turned all 125 of them into a live operations officer: it watches every national feed, works out what's happening to *your* hub, and hands whoever walks through the door their role and their next three tasks.**

One sentence if you're cut short: ***"The hub playbook already exists. We made it read the news."***

One person says it. Same words every time. Twenty seconds.

---

## 2. The problem — with receipts

Verified against live endpoints, 5–6 August 2026.

**a) The most decisive fact in an emergency is not machine-readable anywhere in New Zealand.** "Are we in a declared state of emergency, and where?" No API, national or regional. The process is: email → the mayor physically signs → email back → **a human types a banner onto a website**. WREMO's authoritative status page for 500,000+ people read *"There are currently no emergencies in the Wellington Region"*, timestamped **9 July 2026** — roughly **four weeks stale** when we checked it.

**b) The national warning feed exists and is dark to developers.** NEMA announced a CAP feed for Emergency Mobile Alert and calls it "publicly available." **The URL is published nowhere.** Access starts with an email.

**c) Whole hazard classes have no public feed.** No tsunami warning feed — NEMA issues warnings, GeoNet explicitly doesn't. No FENZ fire danger or live incident API (we enumerated all 30 services in their public ArcGIS org). No NIWA real-time flood API; its one relevant open layer is non-commercial. No public power outage API — Wellington Electricity and Powerco are HTML only.

**d) The feeds that work agree on nothing.** Five formats, two coordinate systems, no shared site IDs, four licences, cadences from seconds to hourly. Every council is a different vendor.

**e) The state of the art is a vendor prototype.** The most advanced thing we found is an Esri experiment harvesting MetService CAP into REST. Its own description states the goal is *"establishing a centralized government hub serving all CAP feeds from multiple agencies in unified REST and OGC formats."* **That hub does not exist.**

**f) And the people at the sharp end have none of it.** 127 hubs. WREMO's words: *"run by people like you in your local community without official assistance,"* roles *"allocated by agreement between whoever turns up,"* equipment is a VHF radio, and *"there are no supplies, food, water or blankets stored at Hubs."*

---

## 3. The trust ladder, and the inversion

Source prioritisation is the most original thing on your whiteboard. Name it, slide it — it's data governance expressed as code, which is the exact expertise gap the mayors raised.

**P0** official/authoritative → act. **P1** official-adjacent → act, cite. **P2** credible secondary → corroborate first. **P3** open web / crowd → signal only, never instruction.

Then the correction, which is your money slide. Your board has NIWA and NEMA at P0. Neither is obtainable: NEMA's URL is unpublished, NIWA has no public real-time API, there's no tsunami feed and no declaration API.

> **The more authoritative a New Zealand emergency source is, the less machine-readable it becomes. Our highest-trust tier is our emptiest tier. That inversion is the problem — and it's why the volunteers at the bottom get nothing.**
>
> *"The fix isn't a startup. It's a URL. And we've asked for it."*

**Email NEMA this morning** so that last line is true.

---

## 4. What makes it a product

**Aggregation alone is a weather app.** Five feeds on one screen is nine browser tabs with better CSS. Judges see that instantly.

**The product is organisational memory — and WREMO already wrote it, 125 times.** Every hub has a published **Community Response Plan**: hub address and facility map marking the kit and the emergency water tank, **four named neighbouring hubs** for resource coordination, kit contents, 18+ local places, 30+ community groups, 10+ services, and named vulnerable-population sites. Plus the regional **Hub Guide** (reviewed July 2025): *Accessing the hub · Working as a team · Setting up · Before you open · Your community's response · Thinking about recovery.*

Plus the **eight official roles** — Hub Supervisor, Information Coordination, Public Information, Reception, Needs and Offers, Community Space, Communications, Facility Maintenance — of which **the first four are designated priority roles.** That gives the AI a real rule for what to fill when only five people turn up.

So the same M5.8 produces different actions at different hubs, because the system read *their* plan. Delete the plan and the product stops working. That's how you know that's the product.

And the reframe of "lack of expertise": the expertise isn't missing, it's *unreachable*. It's in PDFs, at 3am, in the dark.

---

## 5. Architecture

```
┌─ DELIVERY ─────── the EM Board · plain-language chat · one notification channel
├─ REASONING ────── local-first inference · feed state × hub plan → posture + ranked tasks
├─ MEMORY ───────── 125 Community Response Plans + regional Hub Guide + role definitions
├─ NORMALISE ────── one CAP-aligned schema · trust tier · dedupe · geo-match to hub
└─ INGEST ───────── one poll loop, per-feed adapters, cached
```

### The pipeline is one loop, not an event bus

127 hubs and a handful of significant events a day is a few thousand records at peak. A message bus is architecture for a problem two orders of magnitude larger.

```
poll (cron) → normalise to CAP → store in Postgres → match to hub → reason → render
```

One loop, one table, no orchestrator. It fits on a slide, one person can hold it in their head, and it is far easier to demo at 4pm than a distributed system. A queue drops in behind the poller later without touching anything downstream, so deferring costs nothing.

### Normalise to CAP — the decision that carries the scale story

CAP is the WMO-registered international standard. MetService emits it. NEMA emits it. If your internal schema *is* CAP: adding a feed is an adapter, adding a country is adapters, and the day NEMA hands over that URL it's a config change. **Structurally, you are the national CAP aggregator that doesn't exist.**

> *"We didn't invent a schema. We adopted the one the world already agreed on — and found nobody in New Zealand is aggregating it."*

CAP also gives you retraction for free (§8).

### Portable runtime — deploys to a region or to a hall

| Component | Choice | Why |
|---|---|---|
| Compute | Containers + scheduled job | Runs on ECS, a VM, or the Mac Mini. Same artefact. |
| Store | **Postgres + PostGIS** | The data is geospatial — hubs, gauges, closures, hazard extents. Hub→nearest-gauge is a native query, not hand-rolled distance maths. |
| Objects | S3-compatible API | S3 in cloud, MinIO on-prem, same code. |
| Inference | Any OpenAI-compatible endpoint, set by config | Bedrock, Ollama, llama.cpp, vLLM — interchangeable. |

> *"Same containers. Deploy to AWS for a region, or to a Mac Mini in a church hall. No code changes, one config file."*

### Local-first inference — the tiers, in the right order

*This reverses v2. A cloud-default system degrades in exactly the conditions it exists for; a local-default system degrades when it's quiet, which is the correct direction to fail.*

| Tier | Runs on | When |
|---|---|---|
| **Default** | Local model, in the building | Always. Baseline, not fallback. |
| **Burst** | Hosted model | Heavier reasoning when the link is up |
| **Degraded** | Cached last-known-good brief | Inference unavailable |
| **Floor** | Printed brief + the VHF already in the hub kit | Everything else is gone |

> *"Emergency systems fail in exactly the conditions they exist for. So the reasoning layer is swappable: local by default, cloud when there's capacity, cached when there isn't, and the VHF that's already in the cupboard as the floor. Data sovereign, runs in the building, works when the building is cut off."*

Not anti-cloud — the same containers run on AWS at region scale. It just refuses to *require* cloud. Pre-bake the local prompt so it can't embarrass you on stage.

---

## 6. Build list

### Build these six

1. **Collector + trust ladder** — 5 verified feeds, cached fixtures, P-tier tagging, server-side.
2. **Memory — all 125 CRPs** *(reverses v2's "ingest two")*. 125 small PDFs on a common template is minutes of extraction. Doing the full set makes the claim true, makes the parser the reusable artefact, and produces the finding in §7. **Scrape hrefs from the six area pages — never construct URLs.** WREMO uses two inconsistent directories (`/assets/Hub-Guides/` and `/assets/Hub-Guide-CRPs/`) and one file is misspelt `Whitby-CPR`; a naive scraper 404s silently and you'd never notice which hubs vanished.
3. **Reasoning** — feed state × hub plan → posture + ranked tasks, every claim carrying source and timestamp.
4. **The EM Board — one screen.** Absorbs "dashboard," "task," and "assign role/jobs" into one artefact: current picture, then role-assigned task lists generated from the playbook, priority roles filled first.
5. **Age on every fact** — see §8. This is not polish, it is the credibility of the product.
6. **One notification** that says *"something's happening at your hub — get on the board."*

### Cut these, and say you cut them

| Cut | Line |
|---|---|
| Group chat / war room | "The board is the room. Chat is v2." You won't out-build Teams today. |
| SOS / inbound field reports | v2 — and the best thing to be missing, because it's the obvious next slide. |
| Multi-channel fan-out | **Pick one.** Email or one webhook. SMS means Twilio, a number, and a rabbit hole. Architecture slide shows four; demo needs one that works. |
| Reporting to NEMA / WCC / Defence | Slide, not code — and a strong one, it's the accountability leg of the 4Rs. |
| Power outage layer | **No public API exists.** Mock it, label it illustrative, say why — the gap is a finding. |
| Role quiz | Charming, but it's readiness not response. Only if you're ahead at 2pm. |

**Test for anything proposed today:** does it change what the person wearing the Reception lanyard at Newtown does in the next hour? If no, it's a slide.

---

## 7. The staleness map — a free deliverable

Ingesting all 125 plans surfaces a regional readiness picture nobody currently has. We already know: plan dates run **August 2022 → July 2026**; one hub is closed for renovations with a **2019** plan; ~2 of 127 hubs appear to have **no published plan**; filenames and directories are inconsistent.

Present it as *"here are the plans that have gone stale"* and you've handed WREMO something genuinely useful as a by-product — and delivered the **accountability** leg of the original 4R whiteboard without building a feature for it.

---

## 8. The two honesty mechanisms

These are what separate this from a dashboard with an AI bolted on. Both are cheap. Both are demo beats.

### Age on every fact — the sin you must not commit

Your money slide is a four-week-stale hand-typed banner. So the unforgivable failure is **showing something stale as if it were current.** A feed dies at 3am, the board still shows its last value at 9am with no marker, and you've rebuilt WREMO's problem with better typography.

**Rule: every displayed fact carries its age, on its face, not in a tooltip.** `River: rising · 14 min ago`. When age exceeds expected cadence, the tile degrades visibly: `Road closures — last update 4 hours ago, feed may be down`.

Justified by the sources: Metlink reserves the right to change feed URLs **without notice**; GWRC disclaims all liability for reliance on its data. You're building life-safety UX on feeds with no SLA. Surface it rather than pretend.

**And it makes the demo self-demonstrating — kill a feed live on stage and show the board being honest about it.** That beat is worth more than any feature you'd cut to make room for it.

### Retraction — a system that alerts must be able to un-say things

GeoNet withdraws earthquakes; two of three M4+ records we pulled were `quality: "deleted"`. Filtering on read fixes the display, not the claim you already pushed. If the system texts 40 volunteers "M5.2 near Newtown, open the hub" and GeoNet retracts, silence is the worst possible response.

Every alert keyed to its source record, corrections pushed down the same channel. **CAP has this natively** — `msgType: Cancel` / `Update` with `references`. Another dividend from adopting the standard.

> *"Wrong is a state we designed for. Every alert is keyed to its source record, and if that record is withdrawn the correction goes down the same channel it came from. The system can un-say things. Most can't."*

---

## 9. Governance — the landmines are the slide

**Licensing.** The GWRC hub dataset is **CC BY-NC-ND** (NonCommercial *and* NoDerivatives). WREMO's site and guides are **© all rights reserved, no open licence.** Fine for a demo; not clearly OK to redistribute. **Attribute WREMO and GWRC visibly on screen, email info@wremo.nz today, and put "permission requested 6 Aug" on the slide.**

**Privacy — serious.** The CRPs name aged residential care facilities and social housing complexes. **Gate or strip vulnerable-population locations before anything renders publicly.** Do not let the AI surface them to an unauthenticated user on stage.

**Open source boundary — get this precise.** Open-source the **engine**: adapters, CAP normaliser, matcher, board, CRP parser. MIT or Apache 2.0. You **cannot relicense the corpus** — the repo ships *ingestion instructions*, not ingested content; each CDEM group brings its own documents.

> *"The engine is a public good. The content stays with the agency that owns it and is accountable for it. Auckland forks the engine and points it at Auckland's guide."*

Then say the governance line out loud, because it answers the mayors' actual problem with your own build decisions:

> *"On day one we found aged-care addresses in the corpus and gated them, and we dropped the power outage feed because broadcasting 'the lights are off in Island Bay' to an open channel is a burglary map. That's what the missing expertise actually looks like — not knowing the data exists, knowing what not to do with it."*

---

## 10. Competitors — name them before the judges do

**East Gippsland isn't bespoke, it's a product.** `emergencydashboard.eastgippsland.vic.gov.au` runs on **QIT Plus "Guardian Disaster Dashboards"**, deployed at **80+ organisations across Australia, Fiji and Canada**. Aggregates warnings, closures, power, river heights, contacts. **No AI at all, and resident-facing broadcast** — one message, everyone, no reasoning.

> *"The incumbent tells 40,000 residents the same thing. We tell the person wearing the Reception lanyard at Newtown what to do next. Not an AI dashboard — an AI colleague for the person in the lanyard."*

**Hutt City's project is real, and the facts help you.** It's **CERA — GenAI Community Emergency Response Assistant**: funded by the **Bloomberg Philanthropies Mayors Challenge at US$50,000** as one of 50 global finalists — *not* a NZ government AI fund. **Built in-house, no consultancy.** Prototype stage. And **it did not win** — Bloomberg announced 24 winners at US$1M each in February 2026, no New Zealand city among them.

CERA is resident-facing, single-council, multilingual push. You are volunteer-facing, region-wide, grounded in the official playbook. **Complementary: CERA informs residents, you operate the hub.** Naming it with its funder, amount and status reads as real diligence. **Don't claim novelty in multilingual culturally-relevant emergency comms in Lower Hutt — that's verbatim CERA's pitch.**

**Scale note:** the hub model is regional, not national — NEMA publishes no community hub playbook. **Auckland Emergency Management publishes its own Hub Guide**, Hawke's Bay runs hubs too. So rollout is "one ingestion adapter per CDEM group — WREMO first, Auckland second," not "ingest the national playbook," which doesn't exist.

---

## 11. The ADR — write it today, it *is* the scale slide

Four decisions, three sentences each: decision, alternatives, consequences. Twenty minutes, and it converts directly into the "how would this scale" answer the mentor told you to have.

1. **Normalise to CAP**, not a bespoke schema → adding a feed is an adapter; adding a country is adapters.
2. **Portable containers, Postgres/PostGIS, swappable inference**, not cloud-native services → deploys to a region or a hall; no exit cost.
3. **Local-first inference with cloud burst**, not cloud-default → degrades when quiet, not when it matters.
4. **Provenance and age on every fact; retraction via CAP `Cancel`**, not best-effort display → the system can be wrong out loud.

Documentation as pitch asset. Two birds.

---

## 12. The honest limit

Say this out loud. In a room of demos, volunteering it is disarming.

> *"This is advisory, and the human decides. Before it could be authoritative it needs lab validation against historical events, scale testing across all 125 hubs, a deployment path with rollback, and a runbook for the day it's wrong. We built the architecture to survive that process rather than something we'd throw away to pass it."*

---

## 13. Day 2 running order

| Time | Do |
|---|---|
| **Now, 10 min** | Email NEMA for the CAP URL. Email info@wremo.nz for content permission. Register **and subscribe** on the Metlink developer portal — subscription is off by default and you'll 401 without it. Three two-minute tasks that unblock three slides. |
| **Morning** | Ingest all 125 CRPs + Hub Guide. Capture fixtures for all five feeds while they're reachable. Stand up Postgres/PostGIS. |
| **Midday** | The board. One screen, role-assigned tasks from the playbook, **age on every tile**, provenance on every line. |
| **~2pm — hard stop** | **Feature freeze.** Whatever isn't working becomes a slide. There is always one team that demos at 90% and one that demos a crash. |
| **2–4pm** | Write the ADR (20 min). Rehearse the 3 minutes out loud, three times, with the replay running. Assign the hook to one person. |
| **4pm** | Re-verify every endpoint you'll hit on stage. Feeds go down. |

**Pick the replay event now:** a past Wellington southerly with a real MetService CAP warning plus real GWRC river data. Both CAP feeds are empty right now — NZ is quiet — so a live-only demo risks five blank panels.

---

## 14. Demo script — 3 minutes

| Time | Beat |
|---|---|
| **0:00** | **Open on the Newtown CRP PDF.** Scroll it. "This is the official plan for one Wellington hub. It knows the water tank, the neighbouring hubs, the aged-care homes. There are 125 of these. Nobody opens a PDF in an earthquake." |
| **0:25** | 127 hubs, volunteer-run "without official assistance," roles "allocated by agreement between whoever turns up," a VHF radio, no supplies. |
| **0:45** | **The inversion.** Highest-trust sources are the least machine-readable. No declaration API. NEMA's feed URL unpublished — we asked for it this morning. |
| **1:05** | **The board.** Green, and every tile showing its age. Five feeds behind it, trust-tiered. |
| **1:20** | **Replay.** River rising, road closed, warning issued — resolved into one picture, every line sourced and timed. |
| **1:45** | **The money shot.** Same event, two hubs → different actions, because it read *their* plan. Only five people turned up, so it fills the four priority roles first and hands each their tasks — straight out of WREMO's own guide. |
| **2:10** | **Kill a feed live.** The tile degrades and says so. "The system we're replacing was four weeks stale and never said a word." |
| **2:30** | **Governance:** aged-care addresses gated, outage feed dropped, attribution on screen, permission requested. **Then pull the network — the Mac Mini keeps going.** |
| **2:50** | Scale: CAP-native, one adapter per CDEM group, engine open source. Close on the hook. |

**Hold in reserve for Q&A, not stage time:** retraction (§8), the staleness map (§7), the honest limit (§12), the CERA and QIT Plus positioning (§10). Each is a complete answer to a question you will be asked.

**SDGs:** lead with **13.1** (adaptive capacity to climate hazards — still your best fit), then **11.5 / 11.b**, then **4.4**. Support with 9.1, 10.2, 17.16/17.17. Drop 3 and 8.

---

*All external claims verified against live sources 5–6 August 2026. Re-check anything load-bearing before you demo it.*
