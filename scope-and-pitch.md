# The Aggregation Layer — Scope & Pitch
**Tech NZ × AWS AI Hackathon, 5–6 August 2026 · Wellington**

---

## 1. The one-sentence hook

> **There are 127 volunteer-run emergency hubs in the Wellington region. Every one of them is expected to coordinate a disaster response using a VHF radio and whatever expertise happens to walk through the door. We give each one a data-fed operations officer.**

Backup phrasings, depending on the room:

- *"Emergency data in New Zealand isn't missing. It's scattered across nine systems, in five formats, and none of it reaches the volunteers who actually turn up."*
- *"Professional responders have expertise in their heads. Volunteers don't. We put it in the layer between the data and the human."*

**Say this in the first 15 seconds.** Everything else is evidence.

---

## 2. The narrow slice (what you actually build today and tomorrow)

**Audience:** one Community Emergency Hub coordinator in Wellington.
**Scope:** the *readiness → response* transition. Not recovery. Not accountability. Just: *something is developing — what do we do in the next hour?*
**Demo artefact:** one screen + one conversation, driven by five live national/regional feeds and one organisation profile.

Deliberately out of scope — say so on the slide, it reads as discipline rather than gaps:

| Out | Why |
|---|---|
| Asset registers, NetBox, ICT/OT inventory | Leon's real day job, but it's a second problem. Mentioning it broadens the pitch back into fog. |
| Recovery and accountability phases | Different data, different users. |
| Two-way field reporting from volunteers | Obvious v2. Say "v2." |
| Anything requiring a council to sign a contract | You can't sell into government in two days, and you shouldn't have to. Open source is the answer. |

---

## 3. The problem — with receipts

Every claim below was verified against live endpoints today. This is the slide that wins it, because it's not an opinion.

**a) The single most decisive fact in an emergency is not machine-readable anywhere in New Zealand.**
"Are we in a declared state of emergency, and where?" There is no API. Not national, not regional. The declaration process is: email → the mayor physically signs → email back → **a human types a banner onto a website**. When we checked WREMO's authoritative regional status page for 500,000+ people, it read *"There are currently no emergencies in the Wellington Region"* — timestamped **9 July 2026**, roughly **four weeks stale**.

**b) The national public warning feed exists, and is dark to developers.**
NEMA announced a CAP feed for Emergency Mobile Alert and describes it as "publicly available." **The URL is published nowhere.** Access begins with an email and a synchronisation conversation. (Send that email this morning — "we requested it on day one" is a strong line.)

**c) Whole hazard classes have no public feed at all.**
No public tsunami warning feed — NEMA issues warnings, GeoNet explicitly does not. No FENZ fire danger, fire season, or live incident API — we enumerated all 30 services in their public ArcGIS org. No NIWA real-time flood or river API; their one relevant open layer is licensed **non-commercial**.

**d) The feeds that do work don't agree on anything.**
Five formats (GeoJSON, CAP XML, Atom, ArcGIS REST, Hilltop XML), two coordinate systems (EPSG:2193 vs 4326), no shared site IDs, no national schema, cadences from seconds to hourly, and four different licences. Every council is a different vendor.

**e) The state of the art is a vendor prototype.**
The most advanced thing we found is an Esri-hosted experiment harvesting MetService CAP into REST. Its own service description states the objective is *"establishing a centralized government hub serving all CAP feeds from multiple agencies in unified REST and OGC formats."* **That hub does not exist.** That's the thing you're building.

**f) And the people at the sharp end have none of it.**
127 hubs across the region. WREMO's own words: *"The Hub is run by people like you in your local community without official assistance."* Roles are *"allocated by agreement between whoever turns up."* Equipment is a VHF radio. **"There are no supplies, food, water or blankets stored at Hubs."**

**The gap in one line:** national data exists, national coordination doesn't, and the volunteers holding the response together are the furthest from both.

---

## 4. The insight that makes this a product, not a dashboard

This is the crux. Guard it.

**Aggregation alone is a weather app.** Five feeds on one screen is a nicer version of having nine tabs open. Judges will see that instantly.

**The differentiator is organisational memory.** The same national signal must produce *different actions for different organisations*, because the system knows what that organisation is:

- where it is, and what catchment/coast/fault it sits on
- what it's for (welfare shelter vs coastguard vs wildlife monitoring)
- what it has (a hall, a generator, a VHF, 40 volunteers, no water)
- who it serves (elderly residents, a school, a penguin colony)
- what it depends on (one road in, one water main, mains power)

Same M5.8. Same southerly. **Different hour-one actions.**

That reframes "lack of expertise" precisely. Expertise isn't missing facts — the facts are public. Expertise is *converting signals into the next right action for your specific situation*. Professionals carry that conversion in their heads. Volunteers can't, and shouldn't have to. **That conversion is what the layer does.**

---

## 5. Architecture (five layers, one slide)

```
┌─ DELIVERY ────────── hub screen · plain-language chat · SMS/email push · printable brief
├─ REASONING ───────── agent: current state × org profile → posture + ranked actions + provenance
├─ MEMORY ─────────── organisation profile (config, not code)
├─ NORMALISE ───────── one CAP-aligned event schema · dedupe · geo-match to org
└─ INGEST ──────────── per-feed adapters, server-side polling + cache
```

**The one technical decision that carries the whole scale story: normalise to CAP.**
CAP (Common Alerting Protocol) is the WMO-registered international standard. MetService already emits it. NEMA emits it. Every hazard agency on earth either emits it or should. If your internal schema *is* CAP, then:

- adding a feed is writing an adapter, not redesigning the system
- adding a country is adding adapters
- the day NEMA hands over that URL, it's a config change
- **you are, structurally, the national CAP aggregator that doesn't exist**

Say: *"We didn't invent a schema. We adopted the one the world already agreed on, and found that nobody in New Zealand is aggregating it."*

**AWS shape (two lines, if asked):** EventBridge Scheduler → Lambda adapters → DynamoDB + S3 for state and history → Bedrock for the reasoning layer → API Gateway for delivery. Worth noting: **GeoNet already publishes to the AWS Open Data programme**, so the seismic half of this is native to the platform.

---

## 6. The verified feed set (build against these five)

All confirmed live today, all no-auth.

| Feed | Endpoint | Why it's in the demo |
|---|---|---|
| **GeoNet quakes** | `api.geonet.org.nz/quake?MMI=3` · `/intensity?type=reported` | Always has data. Felt reports = human signal, not just instruments. |
| **MetService CAP** | `alerts.metservice.com/cap/rss` | The only WMO-registered NZ CAP feed. Real standards parsing. |
| **NZTA road events** | `services.arcgis.com/CXBb7LAjgIIdcsPt/.../NZTA_Highway_Information/FeatureServer/0/query?f=geojson` | Turns hazard into **access**: "can our people reach the hub?" |
| **GWRC river flow + rainfall** | `mapping.gw.govt.nz/arcgis/rest/services/GW/River_flows_P_2023/MapServer/0` · `.../Rainfall/MapServer/1` | Makes it a *Wellington* demo. Ships `Change: "Rising"` and `Stage_pct` pre-computed — a free "is this river dangerous now" signal. |
| **GeoNet volcanic alert** | `api.geonet.org.nz/volcano/val` | Cheap breadth; Whakaari is at VAL 2 so the tile isn't empty. |

**Also worth 10 minutes:** the Wellington region publishes a **Community Emergency Hubs** layer on the GWRC open data portal (dataset `0c865aef23ec4bbca358d335e5c307cb`). If the geometry is there, you get all 127 hub locations for free — and hub→river-gauge, hub→road-closure proximity joins become trivial. Verify the endpoint early; it's high leverage.

### Four traps that will ruin the demo — fix them before lunch

1. **Both CAP feeds are empty right now.** NZ is quiet. A live-only demo has a real chance of showing five blank panels on stage. **Capture fixtures today**, build a replay toggle, and present the empty state as a feature ("green means quiet").
2. **GeoNet retracts earthquakes.** Filter `quality != "deleted"` — two of three M4+ records we pulled were retracted. Phantom quakes on stage is a bad look.
3. **Reproject NZTA** (`outSR=4326` or `f=geojson`) — native is EPSG:2193, or your points land in the ocean.
4. **Government WAFs block cloud IPs.** `catalogue.data.govt.nz` (Imperva) and `civildefence.govt.nz` blocked us repeatedly. Keep both out of the runtime path. Poll server-side and cache — CORS is undocumented on GeoNet, GWRC and Hilltop, so browser-direct calls should be assumed to fail.

---

## 7. Demo script (3 minutes, tight)

| Time | Beat |
|---|---|
| **0:00** | **Cold open — no slides.** Show WREMO's live status page. Read the timestamp out loud. "This is the authoritative emergency status for half a million people. A human typed it. Four weeks ago." |
| **0:20** | 127 hubs. Volunteer-run, "without official assistance." A VHF radio and no supplies. *This is who we build for.* |
| **0:40** | What that coordinator does today: nine browser tabs, in a storm, at night, possibly without power. |
| **1:00** | **Our screen.** One view. Currently green. Five feeds live behind it. |
| **1:20** | **Replay a real event.** River rising, road closed, warning issued — the aggregation layer resolving it into one picture. |
| **1:40** | **The money shot.** Same event, two organisations — a welfare hub and a coastal wildlife group. *Different actions.* This is the org memory, and it's why this isn't a dashboard. |
| **2:10** | **Ask it something in plain English:** "Do we need to open the hub tonight?" Answer comes back with reasoning and a source + timestamp on every claim. |
| **2:30** | **Scale.** CAP-native, adapters not rewrites, open source so no council is blocked by procurement or by Wellington. Any NZ region, any APAC city. And the gaps we found are the national infrastructure ask: publish the declaration status, publish the CAP feed. |
| **2:50** | SDGs, and close on the hook. |

**Choose the replay event now**, not at 4pm tomorrow. A past Wellington southerly with a real MetService warning plus real GWRC river data is ideal — it lets you demo genuine data on a genuine timeline without depending on the weather cooperating.

---

## 8. Judge objections, pre-answered

**"Isn't this just a dashboard?"**
A dashboard shows you data. We produce a decision, specific to your organisation. Delete the org profile and the product stops working — that's how you know that's the product.

**"Hallucination in an emergency is a liability."**
The model never invents a hazard. It reasons only over retrieved, timestamped records, and every statement carries its source. Unknowns are displayed as unknown. It's advisory, not authoritative — the coordinator decides. And the honest comparison isn't a perfect system, it's nine tabs and a four-week-old banner.

**"What if comms are down?"** *(Leon's insight — use it, it's a genuinely good one)*
There's roughly a 10-minute window after a major event before networks congest, when channels are wide open. An agent can push before the humans start dialling. Then it degrades: SMS, then last-known-good cached locally on the hub device, then the printable brief, then the VHF that's already in the cupboard.

**"Why hasn't the council built this?"**
Procurement cycles, vendor fragmentation, and no in-house data governance capability. Which is the original problem statement. Open source routes around all three.

**"Are you licensed to use this data?"**
GeoNet is CC BY, NZTA is CC BY 4.0, MetService CAP is a public standards feed. We deliberately excluded NIWA's non-commercial layer and MetService's undocumented internal JSON — which ships a licence prohibition in its first field.

**"Privacy?"**
No personal data beyond roles. And visibility is org-controlled by design — one volunteer group we heard about deliberately keeps its little-blue-penguin nest map private so people don't wander in and disturb them. That's the rule, not the exception: aggregation must not mean exposure.

**"It's too broad."** *(the mentor's warning — the real risk)*
One hub. One region. One hour of one event. Five feeds. The breadth is in the *architecture*, and we only claim it in the last 20 seconds.

---

## 9. SDG mapping — three primary, three supporting

You had seven on the board. Seven reads as reaching. Lead with three.

**Primary**

- **13 · Climate Action — target 13.1**, "strengthen resilience and adaptive capacity to climate-related hazards and natural disasters." *This wasn't on your whiteboard and it is your single best fit — it is almost a description of the product. Add it.*
- **11 · Sustainable Cities — 11.5** (reduce disaster losses) and **11.b** (local disaster risk reduction strategies). Hubs *are* 11.b, implemented.
- **4 · Quality Education — 4.4**, relevant skills. Framed correctly: not a training course, **just-in-time capability at the moment of decision.**

**Supporting**

- **9 · Industry, Innovation, Infrastructure — 9.1**, resilient infrastructure. Digital infrastructure counts, and this is the layer that makes physical infrastructure data usable.
- **10 · Reduced Inequalities — 10.2.** A rural volunteer brigade gets the same operational picture as a well-resourced city EOC. That's the equity argument, and it's real.
- **17 · Partnerships — 17.16 / 17.17.** Open source, CAP-standard, cross-agency. Any APAC city forks it and adds their adapters.

Drop 3 and 8 from the pitch. Both are defensible in conversation, neither earns its slide.

---

## 10. What to nail before 12:00

1. **Lock the hook sentence.** Everyone on the team says it the same way.
2. **Pick the replay event.** Then capture fixtures for all five feeds — today, while they're reachable.
3. **Write the two org profiles.** The welfare hub and the wildlife group. This is the demo's centrepiece and it's a text file, not code. Do it before you write an adapter.
4. **Email NEMA** asking for the CAP feed URL. Costs two minutes, earns a slide.
5. **Verify the hub locations layer.** If the geometry's public, your geo-matching story gets much stronger.
6. **Name it.** Boring beats clever. Something that says what it does.

---

*Feed verification: 5 August 2026, all endpoints requested live. Re-check anything load-bearing before you demo it.*
