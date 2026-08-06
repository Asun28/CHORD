# The Aggregation Layer — Scope & Pitch **v2**
**Day 2 · 6 August 2026 · post-iteration**

---

## 1. What changed, and the three things that matter

**a) You found your memory system, and it's already written.**
WREMO publishes a **Community Response Plan (CRP) for every hub** — we counted **~125 published PDFs** (WREMO's site claims 127 hubs, so a couple are missing plans, which is itself a finding). Each one is hub-specific, not boilerplate. The Newtown plan contains: the hub address and a facility map marking the hub kit and emergency water tank, **four named neighbouring hubs** for resource coordination, hub kit contents, 18+ local places, 30+ community groups, 10+ community services, and named vulnerable-population sites.

Plus the regional **Hub Guide** (reviewed July 2025) with six sections: *Accessing the hub · Working as a team · Setting up · Before you open · Your community's response · Thinking about recovery.*

Plus the **eight official roles**, verbatim: Hub Supervisor, Information Coordination, Public Information, Reception, Needs and Offers, Community Space, Communications, Facility Maintenance. **The first four are designated priority roles** — which gives your AI a rule for what to fill first when only five people turn up.

Plus the **"What's your hub role" quiz** is real — 25 agree/disagree statements mapping to the eight roles. Your conversational version of that is a 20-minute build.

**This changes the pitch fundamentally.** You are not proposing to invent guidance. The expertise already exists, WREMO wrote it down 125 times, and it is locked in PDFs that nobody opens during an earthquake. You are making it live. That is a far stronger story than "AI gives advice," and it lands SDG 17 exactly the way Leon wanted: *we didn't build this, we leveraged what the region already built.*

**b) Your P0 tier is the emptiest tier.** See §4. This is the sharpest line in the whole pitch.

**c) Both your competitors are real, and both are beatable — but you must name them first.** See §6. Your funding assumption about Hutt City is wrong in a way that helps you.

**Machine-readable hub locations — confirmed, no token:**
`https://mapping.gw.govt.nz/arcgis/rest/services/GW/Emergencies_P/MapServer/2`
Fields: `NAME, TA_NAME, TYPE, ADDRESS, SUBURB, TOWN, X, Y`. So hub → nearest river gauge → road closure joins are free.

---

## 2. Revised hook

Leon's right that v1 undersold it — it stopped at "information" and you're now doing coordination. Try this:

> **Every one of Wellington's 127 volunteer emergency hubs has an official response plan — naming its neighbouring hubs, its water tank, its aged-care facilities. They're PDFs. Nobody opens a PDF in an earthquake.**
>
> **We turned all 125 of them into a live operations officer: it watches every national feed, works out what's happening to *your* hub, and hands whoever walks through the door their role and their next three tasks.**

Two beats, twenty seconds, no jargon, and the second sentence contains the whole architecture. "Nobody opens a PDF in an earthquake" is the line people will repeat.

If you need one sentence: *"The hub playbook already exists. We made it read the news."*

---

## 3. The scope call — read this one twice

Counting what's now on the board: collector, noise filter, event-driven AI, memory/RAG, notifications across WhatsApp + Teams + SMS, chat/group chat, SOS, task board with role assignment, dashboard, map, reporting out to NEMA/WCC/Defence, the role quiz, and local model inference on a Mac Mini.

**That is a three-month product. You have roughly seven hours.** This is precisely the failure the mentor warned about yesterday, and it now has a floor plan. Cut hard, now, while cutting is still cheap.

### Build (the demo is these five things)

1. **Collector + trust ladder** — 5 verified feeds, cached fixtures, P-tier tagging. Server-side, cached.
2. **Memory** — the regional Hub Guide + **two** CRPs (Newtown and one contrasting hub). Two, not 125. Say "125" on the slide; ingest two.
3. **Event-driven reasoning** — feed state × hub CRP → posture + ranked actions, every claim carrying its source and timestamp.
4. **The EM Board — one screen.** This is the demo. It absorbs "dashboard," "task," and "assign role/jobs" into a single artefact: current picture, then role-assigned task lists generated from the playbook.
5. **One notification** that says *"something's happening at your hub — get on the board."*

### Cut (and say you cut them, deliberately)

| Cut | Line to use |
|---|---|
| Group chat / war room | "The board is the room. Chat is v2." You will not out-build Teams today, and the board carries the value. |
| SOS / inbound field reports | v2. It's the obvious next slide, and it's the only thing missing from a complete story — which makes it a *good* thing to be missing. |
| Multi-channel fan-out (WhatsApp + Teams + SMS) | **Pick one.** Email or a single webhook into a Teams/Slack channel. SMS means Twilio, a number, and a rabbit hole. The architecture slide can show four channels; the demo needs one that works. |
| Reporting out to NEMA / WCC / Defence | Slide, not code. And it's a strong slide — it's the accountability loop from the original whiteboard. |
| Power outage layer | **No public API exists.** Wellington Electricity and Powerco are HTML-only, no licence, no endpoint. Mock it, label it illustrative, and say why — that gap is a finding, not a failure. |
| Role quiz | Cheap and charming, but it's readiness, not response. Do it only if you're ahead at 2pm. |

**The test for anything else that gets suggested today:** does it change what the person wearing the Reception lanyard at Newtown does in the next hour? If no, it's a slide.

---

## 4. The trust ladder — your best original idea, and a correction

P0→P3 source prioritisation is the most genuinely novel thing on that whiteboard, and it's the answer to "how is this different from Google Maps." **Name it and put it on a slide.** It's data governance expressed as code — which is the exact problem the mayors raised.

Something like: **P0 official/authoritative — act on it. P1 official adjacent — act, note the source. P2 credible secondary — corroborate before acting. P3 open web / crowd — surface as signal only, never as instruction.**

**Now the correction, and it's the best line in your pitch.** Your board has NIWA and NEMA at P0. Neither is available:

- **NEMA's CAP feed** exists and NEMA calls it publicly available — **the URL is published nowhere.** Access starts with an email.
- **NIWA has no public real-time river or flood API.** Its one relevant open layer is licensed non-commercial.
- **No public tsunami warning feed exists** anywhere — NEMA issues warnings, GeoNet explicitly doesn't.
- **No machine-readable state-of-emergency declaration**, at any level, in the country.

So:

> **The more authoritative a New Zealand emergency source is, the less machine-readable it becomes. Our highest-trust tier is our emptiest tier. That inversion is the problem — and it's why the volunteers at the bottom get nothing.**

That's your money slide. It's verified, it's counter-intuitive, no judge will have heard it, and it converts your gaps from weaknesses into the finding. Then: *"the fix isn't a startup, it's a URL — and we've asked for it."*

**Email NEMA this morning.** Two minutes, earns the slide.

**Also, yes on public transport** — Metlink GTFS-Realtime includes machine-readable **service alerts**, free API key. **Register AND subscribe to the API product** on the developer portal — subscription is off by default and you'll 401 without it. Do that now, not on stage. Static GTFS needs no key: `https://static.opendata.metlink.org.nz/v1/gtfs/full.zip`

---

## 5. Licence and privacy — turn the landmines into the governance slide

Two real risks, and handled well they become the most credible part of your pitch.

**Licensing.** The GWRC hub dataset is **CC BY-NC-ND** — NonCommercial *and* NoDerivatives, and "NoDerivatives" is awkward for a transformed knowledge base. The WREMO site and guides are **© all rights reserved, no open licence**. Fine for a hackathon demo; not clearly OK to redistribute. **Attribute WREMO and GWRC visibly on screen, email info@wremo.nz today, and put "permission requested 6 Aug" on the slide.** Judges read that as maturity.

**Privacy — this one is serious.** The CRPs name aged residential care facilities and social housing complexes. **Gate or strip vulnerable-population locations before anything is displayed publicly**, and do not let the AI surface them to an unauthenticated user in the demo.

And then say this out loud, because it's the whole original problem in one beat:

> *"On day one we found aged-care addresses in the corpus and gated them, and we dropped the power outage feed because broadcasting 'the lights are off in Island Bay' to an open channel is a burglary map. That's what the missing expertise actually looks like — not knowing the data exists, knowing what not to do with it."*

That is the "lack of data governance expertise" problem from the first whiteboard, answered by your own build decisions. Leon's outage/burglary instinct from yesterday is exactly right — use it.

---

## 6. Competitors and prior art — name them before the judges do

**East Gippsland is not a one-off. It's a product.**
`https://emergencydashboard.eastgippsland.vic.gov.au/` runs on **QIT Plus "Guardian Disaster Dashboards"**, deployed at **80+ organisations across Australia, Fiji and Canada** (Byron, Balonne, Diamantina, Flinders). It aggregates warnings, road closures, power, river heights, contacts. **It has no AI whatsoever, and it's resident-facing broadcast** — one message, everyone, un-personalised, no reasoning.

> *"The incumbent tells 40,000 residents the same thing. We tell the person wearing the Reception lanyard at Newtown what to do next. Not an AI dashboard — an AI colleague for the person in the lanyard."*

**Hutt City's project is real, and your assumptions about it are wrong in your favour.**
It's called **CERA — GenAI Community Emergency Response Assistant**. Correct record: funded by the **Bloomberg Philanthropies Mayors Challenge at US$50,000** as one of 50 global finalists — *not* a NZ government AI fund. **Built in-house by the council, no consultancy named.** Still at prototype stage. And **it did not win** — Bloomberg announced 24 winners at US$1M each in February 2026, and no New Zealand city is on that list.

CERA is **resident-facing, single-council, multilingual push messaging**. You are **volunteer-facing, region-wide, and grounded in the official hub playbook**. Position as complementary: *CERA informs residents; we operate the hub.* Being able to name it, its funder, its exact amount, and its status will read as real diligence. **Do not claim novelty in multilingual culturally-relevant emergency comms for Lower Hutt — that is verbatim CERA's pitch.**

**One more useful fact for the scale story:** the hub model is regional, not national. NEMA publishes no community hub playbook. **Auckland Emergency Management publishes its own Hub Guide PDF**, and Hawke's Bay runs hubs too. So national rollout is "one ingestion adapter per CDEM group — WREMO first, Auckland second," not "ingest the national playbook," which doesn't exist.

---

## 7. The Mac Mini call

The local-model instinct is right and the demo theatre is excellent — but don't bet the whole pitch on local inference quality over hackathon wifi, and remember you're pitching at an AWS event.

**Do this instead: make the model a swappable tier, and demo the degradation.**

1. Main demo runs on a hosted model — reliable, fast, no stage risk.
2. Then the closing beat: **pull the network. The Mac Mini keeps answering.**

> *"Emergency systems fail in exactly the conditions they exist for. So the reasoning layer is swappable: cloud when the link's up, local when it isn't, cached brief when even that's gone, and the VHF that's already in the hub kit as the floor. Data sovereign, runs in the building, works when the building's cut off."*

That reframes local models as **resilience architecture** rather than a preference — which is stronger, honest, and AWS-compatible (hybrid edge is a real pattern, not a snub). Pre-bake the local prompt so it can't embarrass you.

---

## 8. Day 2 running order

| Time | Do |
|---|---|
| **Now, 10 min** | Email NEMA for the CAP URL. Register + **subscribe** on the Metlink portal. Both are two-minute tasks that unblock slides. |
| **Morning** | Scrape the two CRPs + Hub Guide into memory. **Scrape hrefs from the six area pages — never construct URLs**; WREMO uses two inconsistent directories (`/assets/Hub-Guides/` and `/assets/Hub-Guide-CRPs/`), one file is misspelt `Whitby-CPR`, and a naive scraper silently 404s. Capture fixtures for all five feeds while they're reachable. |
| **Midday** | The board. One screen, role-assigned tasks out of the playbook, provenance on every line. |
| **~2pm — hard stop** | **Feature freeze.** Whatever isn't working becomes a slide. This is the discipline that wins hackathons; there is always one team that demos at 90% and one that demos a crash. |
| **2–4pm** | Rehearse the 3 minutes out loud, three times, with the replay running. Assign who says the hook — one person, same words. |
| **4pm** | Re-verify every live endpoint you plan to hit on stage. Feeds go down. |

**Pick the replay event now** if you haven't: a past Wellington southerly with a real MetService CAP warning plus real GWRC river data. Both CAP feeds are empty right now — NZ is quiet — so a live-only demo risks five blank panels.

---

## 9. Revised demo script (3 min)

| Time | Beat |
|---|---|
| **0:00** | **Open on the Newtown CRP PDF.** Scroll it. "This is the official plan for one Wellington hub. It knows the water tank, the neighbouring hubs, the aged-care homes. There are 125 of these. Nobody opens a PDF in an earthquake." |
| **0:25** | 127 hubs, volunteer-run "without official assistance," roles "allocated by agreement between whoever turns up," a VHF radio, no supplies. |
| **0:45** | **The inversion slide.** Highest-trust sources are the least machine-readable. No declaration API. NEMA's feed URL unpublished — we asked for it this morning. |
| **1:05** | **The board.** Green. Five feeds behind it, trust-tiered. |
| **1:20** | **Replay.** River rising, road closed, warning issued — resolved into one picture, every line sourced and timestamped. |
| **1:45** | **The money shot.** Same event, two hubs → different actions, because the AI read *their* plan. Then: only five people turned up, so it fills the four priority roles first and hands each one their tasks — straight out of WREMO's own guide. |
| **2:15** | **Governance.** We gated aged-care addresses. We dropped the outage feed. Attribution on screen, permission requested. |
| **2:35** | **Pull the network. The Mac Mini keeps going.** |
| **2:50** | Scale: CAP-native, one adapter per CDEM group, open source so no council waits on procurement. Close on the hook. |

**SDGs:** lead with **13.1** (adaptive capacity to climate hazards — still your best fit and still not on the whiteboard), then **11.5/11.b**, then **4.4**. Support with 9.1, 10.2, 17.16/17.17. Drop 3 and 8.

---

*All external claims verified against live sources 5–6 August 2026. Re-check anything load-bearing before you demo it.*
