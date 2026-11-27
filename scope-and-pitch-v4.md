# The Aggregation Layer: Scope & Pitch **v4**
**Day 1 evening · 6 August 2026 · supersedes v3**

*v3's analysis stands. This version aligns it to the challenge: real SDG targets with official indicators, the working-backwards pack the mentors will ask for, and a 5-minute script matching the AI Forum structure.*

**Judging:** tomorrow from 3pm, prizes 5pm. Rehearsals with mentors from noon. **5 minutes, strictly enforced, standardised across venues.**
**Judges:** Nicola (sustainability lead, Woolworths NZ: circularity; *prior career in analytics*), Jane Shepard (end-to-end data, incl. data science and computational science, NZ Institute for Public Health and Forensic Science), Robin Holloway (public policy manager, AWS; *career began in innovation policy at MBIE*).

**Read the judge panel:** two of the three are data professionals, so "how will you measure success" is not a throwaway slide: §3 exists for them. The third is public policy with an innovation-policy background, so your closing asks (§9) are aimed at her: they are policy asks, not funding asks.

---

## 1. The hook

> **114 of Wellington's 125 volunteer emergency hubs have a published response plan, each naming its neighbouring hubs, its water tank, its aged-care facilities. They're PDFs. Nobody opens a PDF in an earthquake.**
>
> **We turned all 114 of them into a live operations officer: it watches every national feed, works out what's happening to *your* hub, and hands whoever walks through the door their role and their next three tasks.**

One sentence: ***"The hub playbook already exists. We made it read the news."***

---

## 2. SDG alignment

The brief was explicit: tie back to the goals or the judges can't score you. Do it with **targets and indicators**, not seventeen logos. Three primary goals, one slide, one measurable indicator each.

### Anchor everything to Sendai first

SDG targets 11.b and 13.1 both explicitly reference the **Sendai Framework for Disaster Risk Reduction 2015 to 2030**, which New Zealand has endorsed. Two parts of Sendai describe this product almost verbatim:

- **Target G**: *substantially increase the availability of and access to multi-hazard early warning systems and disaster risk information and assessments to the people by 2030.* That is the aggregation layer, stated as an international commitment.
- **Priority 4**: *enhancing disaster preparedness for effective response.*

Opening the SDG slide with Sendai rather than a goal number signals domain literacy immediately, and it makes the SDG mapping look derived rather than retrofitted, which it now is.

### Primary: three goals

**SDG 13 · Climate Action: target 13.1**
*"Strengthen resilience and adaptive capacity to climate-related hazards and natural disasters in all countries."*
Almost a description of the product. Official indicator **13.1.3: proportion of local governments that adopt and implement local disaster risk reduction strategies in line with national strategies.** Community Response Plans *are* those local strategies: and we can measure how many are current.

**SDG 11 · Sustainable Cities and Communities: targets 11.5 and 11.b**
11.5: reduce deaths, people affected, and economic losses from disasters, *"with a focus on protecting the poor and people in vulnerable situations"*, which is precisely the vulnerable-population data in the CRPs, and precisely why we gated it. 11.b: implement holistic disaster risk management at all levels, in line with Sendai. Indicator **11.b.2 is the same measurement as 13.1.3**, one number serves two goals.

**SDG 16 · Peace, Justice and Strong Institutions: targets 16.10 and 16.6**
16.10: *public access to information.* 16.6: *effective, accountable and transparent institutions at all levels.* This is where your central finding lives: the most decisive emergency information in the country is not accessible to the people who need it, and a four-week-stale hand-typed banner is not a transparent institution. Indicator **16.10.2** concerns policy guarantees of public access to information; our contribution is a measured baseline of how few authoritative emergency sources are actually accessible.

**Adding 16 also claims a second lane of the challenge's five Ps: Peace alongside People.**

### Supporting: mention only if asked

- **SDG 4 · Quality Education: 4.4.** Stronger than it first looks: indicator **4.4.1 measures ICT skills**, and the original problem the mayors raised was digital and data governance capability. Honest framing: we build just-in-time capability at the point of decision, not formal education. Don't lead with it.
- **SDG 9 · 9.1** resilient infrastructure: digital infrastructure counts, and this is the layer that makes physical infrastructure data usable.
- **SDG 10 · 10.2** a rural volunteer brigade gets the same operational picture as a well-resourced city EOC. Real equity argument.
- **SDG 17 · 17.16/17.17** open-source engine, CAP standard, cross-agency. The partnership lane.
- **SDG 3 · 3.d** *"strengthen the capacity... for early warning, risk reduction and management of national and global health risks."* Early warning is named in the target. Worth having ready given one judge's public-health background.

**Retire 8 from the pitch.** Defensible in conversation, doesn't earn a slide.

### Lane: **People** primary, **Peace** and **Partnership** secondary. Not Planet, not Prosperity: don't reach.

---

## 3. How we measure success

Keith's fifth question, and the slide the two data judges will actually interrogate. Every row below is computable: three of them from work you're doing today.

| Goal / target | Official indicator | What we measure | Baseline today |
|---|---|---|---|
| **13.1 / 11.b** | 13.1.3 & 11.b.2, proportion of local governments implementing local DRR strategies | **% of the region's 125 hubs with a current published response plan**, our staleness map | **Unknown and unreported.** Nobody publishes this. We can produce it tonight. |
| **11.5** | 11.5.1 persons directly affected; 11.5.2 disruption to basic services | **Minutes from national signal → hub-actionable instruction** | **No automated path exists.** Today it's a human noticing a website. |
| **16.10 / 16.6** | 16.10.2 guarantees of public access to information | **Count of authoritative NZ emergency sources that are machine-readable** | **Measured: declaration status 0, tsunami warnings 0, fire danger 0, NEMA CAP feed published-but-unlisted.** |
| **4.4** | 4.4.1 ICT skills | **Guide questions answered without the supervisor**; **volunteers correctly role-matched on arrival** | Every question goes to the one person who read the 44 pages. |

The first row is the strongest thing you can say to an analytics judge: **"we can report an official SDG indicator for this region that currently nobody reports."** That is not a projection. That's a number you'll have before you present.

---

## 4. Working backwards: the pack the mentors will ask for

### The two personas

**Moana: the one who's read it.** Volunteer hub coordinator, works in retail, did a WREMO session eighteen months ago, has skimmed the 44-page guide once. She's the 1 to 2% who roughly know the drill.
*Goals:* get the hub open, get people useful, get a picture of what's happening, get word to the EOC.
*Pains:* she becomes a help desk within ten minutes. Everyone asks her everything. She's drawing a roster on paper while trying to work out whether the road to the supermarket is open. She has no idea what's happening outside her own street. The VHF is for emergencies, not questions.
*What she has:* a laptop, a whiteboard, tape, a VHF radio, and a school hall that, crucially, **has power when the houses don't.** That's why people walk to it.

**Dave: the walk-in.** Turns up wanting to help. Never seen the guide.
*Goals:* be useful in the next five minutes; not be in the way.
*Pains:* doesn't know where the key is, what's needed, or who's in charge. Default outcome is standing around, or adding to the queue in front of Moana.

*(Third persona if asked: the EOC duty officer, who currently has no visibility of whether a hub has even opened.)*

### What we know about them, and what we don't

**Know**, from WREMO's own published material: the hub is *"run by people like you in your local community without official assistance"*; roles are *"allocated by agreement between whoever turns up"*; *"there are no supplies, food, water or blankets stored at Hubs"*; equipment is a VHF radio; the guide runs to 44 pages; there are **eight defined roles**, Hub Supervisor, Information Coordination, Public Information, Reception, Needs and Offers, Community Space, Communications, Facility Maintenance, of which **the first four are designated priority roles**; the situation board is built from *"whiteboard, sheets, paper, pins, tape"*; 114 of the 125 hubs have a published Community Response Plan and 11 have none.

**Don't know (Keith explicitly asks for this, so say it out loud):** how many volunteers actually arrive in the first hour; whether a coordinator would trust a machine-generated roster; what device is actually available at a given hub; whether the VHF channel is used for status or only for emergencies; how often hubs activate at all. **Name these as your validation plan.** Most teams will pretend they have no unknowns; saying yours is a scoring asset, not a weakness.

### The most impactful problem: pick one and say only this one

> **In the first hour, a hub's entire response is bottlenecked on one person answering questions that a document already answers.**

Everything else, the roster, the situation board, the feeds, is downstream of that. The guide tells you *what* to do. It doesn't *do* it. It says "create a roster," and you reach for paper and draw boxes.

### The benefit, in the persona's words

Moana stops being a help desk and starts coordinating. Dave has a role and three tasks within minutes of walking in. The four priority roles get filled first because the system knows they're the priority. The situation picture is shared, current, and honest about how old it is.

### The customer experience: narrate this, don't diagram it

Dave walks in. There's a screen. He answers two questions. He's Reception, with a lanyard, and three tasks from WREMO's own guide. Moana sees the region on one board (river rising, road closed, warning issued), every line stamped with its source and its age. At thirty minutes the board reminds her nobody's had an update. She never opened the PDF.

### Mock press release: the Amazon device, 90 seconds to read

> **Wellington's 125 volunteer emergency hubs can now run a coordinated response from the first minute.**
>
> *Wellington, NZ*: Community Emergency Hubs across the Wellington region today gained access to an open-source coordination layer that turns the region's 114 published hub response plans into live operational guidance.
>
> Until now, a hub opening in an emergency depended on whoever walked through the door and on a 44-page printed guide. Roles were assigned by agreement, rosters were drawn on paper, and the region's authoritative emergency status was a hand-updated web banner that had gone four weeks without a change.
>
> The new layer continuously reads national and regional hazard feeds (earthquakes, severe weather, road closures, river levels), normalises them to the international CAP standard, and interprets them against each hub's own published response plan (114 of the region's 125 hubs have one). Volunteers arriving at a hub are matched to one of the eight official roles, priority roles first, and given tasks drawn from the guide itself. Every fact displayed carries its source and its age, and any alert can be withdrawn if its source record is retracted.
>
> "The expertise was never missing," said a hub coordinator. "It was in a document I didn't have time to read."
>
> The engine is open source. Each emergency management group brings its own plans.

---

## 5. The problem: receipts

Verified against live endpoints 5 to 6 August 2026.

**a)** No machine-readable state-of-emergency declaration exists anywhere in New Zealand. The process is email → the mayor physically signs → email back → **a human types a banner.** WREMO's authoritative status page for 500,000+ people read *"no emergencies in the Wellington Region"*, timestamped **9 July 2026**: four weeks stale.
**b)** NEMA's Emergency Mobile Alert CAP feed exists and is described as publicly available. **The URL is published nowhere.** Access starts with an email.
**c)** No public tsunami warning feed. No FENZ fire danger or live incident API (all 30 services in their public ArcGIS org enumerated). No NIWA real-time flood API. No public power outage API.
**d)** The feeds that work agree on nothing: five formats, two coordinate systems, four licences, no shared IDs.
**e)** The state of the art is a vendor prototype whose own description says the goal is *"establishing a centralized government hub serving all CAP feeds."* **That hub does not exist.**

---

## 6. The trust ladder, and the inversion

**P0** authoritative → act. **P1** official-adjacent → act, cite. **P2** credible secondary → corroborate. **P3** open web / crowd → signal only, never instruction.

Data governance expressed as code: the exact capability gap the mayors raised. Then the correction: your board had NIWA and NEMA at P0 and neither is obtainable.

> **The more authoritative a New Zealand emergency source is, the less machine-readable it becomes. Our highest-trust tier is our emptiest tier.**
>
> *"The fix isn't a startup. It's a URL. And we've asked for it."*

---

## 7. What makes it a product

Aggregation alone is a weather app. **The product is organisational memory, and WREMO already wrote it 114 times.** 114 of the 125 hubs have a published Community Response Plan: facility map with the kit and the emergency water tank, four named neighbouring hubs, kit contents, 18+ local places, 30+ community groups, named vulnerable-population sites. Plus the regional Hub Guide's six sections and the eight roles with four priorities.

Same M5.8, different hubs, different actions, because it read *their* plan. Delete the plan and the product stops working. That's how you know that's the product.

**And concede paper immediately.** EOC coordinators love paper, paper needs no power, paper is more resilient. Then:

> *"We're not replacing the whiteboard. We're replacing the queue of people standing behind the one person who's read the guide."*

Paper can't answer questions, and it can't notice absence, which is why the thirty-minute nudge is a small feature with a disproportionate demo moment.

**Scope boundary, state it as a non-goal:** this is the *coordination* layer for the hub. The resident-facing layer is a different product (and it's CERA's, see §10). **Asset tracking is out**: check-in/check-out compliance is a human problem tech doesn't fix. **Needs and Offers stays**, because it's role five in WREMO's own guide, it's a matching problem, and it has no compliance dependency.

---

## 8. Architecture

```
┌─ DELIVERY ─────── the EM Board · plain-language chat · one notification channel
├─ REASONING ────── local-first inference · feed state × hub plan → posture + ranked tasks
├─ MEMORY ───────── 114 Community Response Plans + Hub Guide + role definitions
├─ NORMALISE ────── one CAP-aligned schema · trust tier · dedupe · geo-match to hub
└─ INGEST ───────── one poll loop, per-feed adapters, cached
```

**One loop, not an event bus.** `poll (Cron Trigger) → normalise to CAP → store in D1 → match to hub → reason → render`. 125 hubs and a handful of events a day is not a throughput problem. A queue drops in behind the poller later at zero cost.

**Normalise to CAP**: the WMO standard MetService and NEMA already emit. Adding a feed is an adapter; adding a country is adapters; the day NEMA hands over the URL it's a config change. Structurally you become the national CAP aggregator that doesn't exist. It also gives you retraction for free.

**Portable runtime (ADR-010):** one Cloudflare Worker built with vinext · a Cron Trigger for the poll loop · **D1** as the store (hub-to-area matching is point-in-polygon in TypeScript) · secrets through `wrangler secret` · any OpenAI-compatible inference endpoint set by config.

> *"Same Worker. Deploy it to Cloudflare for a region, or run it under wrangler with a local D1 on a laptop in a church hall. No code changes."*

**Local-first inference tiers:** local model in the building (default) → hosted model (burst) → cached last-known-good brief (degraded) → printed brief + the VHF already in the kit (floor). A cloud-default system degrades in exactly the conditions it exists for.

### The two honesty mechanisms

**Age on every fact.** Your money slide is a four-week-stale banner, so the unforgivable failure is showing something stale as current. Age on the face of every tile, not in a tooltip. `River: rising · 14 min ago`. When age exceeds cadence, the tile degrades visibly. Justified by the sources themselves: Metlink reserves the right to change feed URLs *without notice*; GWRC disclaims liability for reliance. **This makes the demo self-demonstrating: kill a feed on stage.**

**Retraction.** GeoNet withdraws earthquakes. Once you've pushed to 40 volunteers you must be able to un-push. Every alert keyed to its source record; corrections down the same channel. **CAP does this natively**: `msgType: Cancel`/`Update` with `references`.

---

## 9. Governance, and what we'd need

**Licensing.** GWRC hub dataset is **CC BY-NC-ND**. WREMO's site and guides are **© all rights reserved.** Attribute both visibly on screen; email info@wremo.nz; put "permission requested 6 Aug" on the slide.
**Privacy.** CRPs name aged-care facilities and social housing. **Gate vulnerable-population locations before anything renders.**
**Open source boundary.** Engine open source (adapters, normaliser, matcher, board, parser). **The corpus is not yours to relicense**: the repo ships ingestion instructions, and each CDEM group brings its own documents.

> *"On day one we found aged-care addresses in the corpus and gated them, and we dropped the power outage feed because broadcasting 'the lights are off in Island Bay' to an open channel is a burglary map. That's what the missing expertise actually looks like: not knowing the data exists, knowing what not to do with it."*

### "What would you need to make this work": the closing slot

The brief asks for people, technology, time, datasets. Yours are mostly **policy**, which is unusual and lands directly with an innovation-policy judge:

1. **Publish the state-of-emergency declaration as data.** One endpoint. It changes the national picture and costs nothing.
2. **Publish the NEMA CAP feed URL** that already exists and is already described as public.
3. **Content permission from WREMO**, and ideally an open licence on hub guides so every region can build on them.
4. **One CDEM group as a pilot**, with a device at each hub.
5. **Validation we can't do in two days:** replay against historical events, scale test across all 125 hubs, a deployment path with rollback, and a runbook for the day it's wrong.

Then the honest limit, said out loud (in a room of demos, volunteering it is disarming):

> *"This is advisory, and the human decides. We built the architecture to survive proper validation rather than something we'd throw away to pass it."*

---

## 10. Competitors: name them before the judges do

**East Gippsland isn't bespoke, it's a product.** It runs on **QIT Plus "Guardian Disaster Dashboards"**, deployed at **80+ organisations across Australia, Fiji and Canada**. **No AI, resident-facing broadcast**: one message, everyone, no reasoning.

> *"The incumbent tells 40,000 residents the same thing. We tell the person wearing the Reception lanyard at Newtown what to do next. Not an AI dashboard: an AI colleague for the person in the lanyard."*

**Hutt City's CERA**: GenAI Community Emergency Response Assistant. **Bloomberg Philanthropies Mayors Challenge, US$50,000**, one of 50 finalists, built in-house, prototype stage, and **it did not win** (24 winners at US$1M in Feb 2026, no NZ city). Resident-facing, single-council, multilingual push. **Complementary: CERA informs residents, you operate the hub.** Don't claim novelty in multilingual emergency comms for Lower Hutt, that's verbatim CERA's pitch.

**Scale note:** the hub model is regional, not national. NEMA publishes no community hub playbook; **Auckland Emergency Management publishes its own.** So rollout is one ingestion adapter per CDEM group: WREMO first, Auckland second.

---

## 11. The 5-minute script

Strictly timed. **One person carries all five minutes**: at strict time, handoffs are where teams bleed. Someone else drives the screen.

### 0:00 to 0:30 · Connect

> "I'm Leon. I've spent six years inside the digital infrastructure of New Zealand councils.
>
> Three weeks ago I asked Wellington's emergency public information officer what actually happens when a state of emergency is declared. He said: we email the mayor. The mayor prints it, signs it, emails it back. Then a person types a banner onto a website.
>
> I checked that website yesterday. It says there are no emergencies in the Wellington region. It was last updated four weeks ago."

### 0:30 to 1:30 · The problem, human

> "There are 125 Community Emergency Hubs in this region. When one opens, whoever walks through the door has to become an emergency response team.
>
> WREMO's own guide says the hub is *run by people like you in your local community, without official assistance.* Roles are *allocated by agreement between whoever turns up.* And there are *no supplies, food, water or blankets stored at hubs.*
>
> What there is: a VHF radio, and a 44-page guide.
>
> Yesterday, five technologists sat in a room and read a question out of that guide. *Do you know where the key is?* Nobody did.
>
> And that's the real problem. One or two people have read the guide. Everyone else queues behind them, asking questions the document already answers, while those one or two people are trying to run a response."

### 1:30 to 2:30 · The big idea

> "The expertise isn't missing. WREMO wrote it down. A 44-page regional guide, and a separate response plan for 114 of the region's 125 hubs.
>
> Newtown's plan names its emergency water tank. Its four neighbouring hubs. Its three aged-care facilities.
>
> There are 114 of them, and they're PDFs. Nobody opens a PDF in an earthquake.
>
> So we made the playbook read the news. Five national feeds (earthquakes, severe weather, road closures, river levels), normalised to CAP, the international alerting standard, then interpreted against your hub's own plan.
>
> And here's what we found while looking for news to read: **the more authoritative a New Zealand emergency source is, the less machine-readable it becomes.** There is no API for whether a state of emergency has been declared. No public tsunami feed. NEMA's alert feed exists: the URL is published nowhere. Our highest-trust tier is our emptiest tier."

### 2:30 to 3:45 · The prototype

Board · every tile showing its age → **replay** a real event → **two hubs, different actions** → only five people turned up, so **the four priority roles fill first**, each with tasks from WREMO's guide → **kill a feed live**, the tile degrades and says so.

> "The system we're replacing was four weeks stale and never said a word."

### 3:45 to 4:30 · Impact and measurement

> "Sendai Target G commits countries to increase access to multi-hazard early warning and risk information. SDG 13.1 and 11.b point straight at it, and their official indicator is the proportion of local governments implementing local disaster risk reduction strategies.
>
> Those plans *are* those strategies. So we can report that indicator for this region, the share of the 125 hubs with a current plan, and nobody currently reports it. We found plans dated 2022, one hub closed with a 2019 plan, and 11 with no published plan at all.
>
> Second measure: minutes from a national signal to an instruction a hub can act on. Today there's no automated path at all.
>
> Third: SDG 16.10, public access to information: a count of authoritative emergency sources that are machine-readable. Declaration status: zero."

### 4:30 to 5:00 · The ask and the close

> "What we'd need isn't funding. It's three things. Publish the declaration as data. Publish the CAP feed URL that already exists. And an open licence on the hub guides, so every region can build on what Wellington already wrote.
>
> The engine is open source. The plans stay with the agency accountable for them.
>
> The hub playbook already exists. We made it read the news."

**Hold for Q&A, not stage time:** retraction, paper-vs-digital, competitors, privacy gating, the honest limit, the Mac Mini. Each is a complete answer.

---

## 12. Running order

Historical hackathon running order (August 2026), kept as written. ADR-010 supersedes its runtime steps: the store is D1, not Postgres/PostGIS, and the hall node runs under wrangler with a local D1.

| When | Do |
|---|---|
| **Now → 5pm** | Ingest all 114 published CRPs. Capture feed fixtures. Postgres/PostGIS up. Board skeleton. Email NEMA and WREMO: both unblock slides. Register **and subscribe** on the Metlink portal (subscription is off by default; you'll 401 without it). |
| **Overnight** | Local model on the Mac Mini; offline behaviour; board polish. Good unsupervised work, and it's your closing beat. |
| **Tomorrow 9:00 to 11:30** | Compute the staleness numbers. Fixtures verified. Three dry runs. |
| **11:30** | **Feature freeze.** Anything unfinished becomes a screen: the brief says clickable or hi-fi screens are fine, so don't debug what a screenshot would carry. |
| **12:00** | Mentor rehearsal. Bring §4 written down; Keith will ask his five questions. |
| **2:30** | Re-verify every endpoint you'll touch on stage. |
| **3:00** | Pitch. |

**Pick the replay event now:** a past Wellington southerly with a real MetService CAP warning plus real GWRC river data. Both CAP feeds are empty right now, NZ is quiet, so a live-only demo risks blank panels.

---

*All external claims verified against live sources 5 to 6 August 2026. Re-check anything load-bearing before you demo it.*
