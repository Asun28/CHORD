# Omega Engineering Review — Hackathon Pitch v2
**6 August 2026 · reviewed against Omega Networks engineering standards**

A hackathon and "do it properly from the beginning" are in genuine tension, so this review separates two questions and grades them differently:

- **The architecture** — judged by Omega's standards, because these decisions outlive the weekend.
- **The demo** — judged by hackathon standards, because it's disposable by design.

The risk isn't making throwaway choices today. It's failing to label which ones are throwaway, so that a demo shortcut quietly becomes the product.

---

## Scorecard — Omega's seven-point framework

| # | Criterion | Verdict | Note |
|---|---|---|---|
| 1 | **Will it last?** | **Pass** | CAP is a 20+ year international standard, still current, still the thing NEMA and MetService emit. You adopted rather than invented. This is the strongest decision in the pitch. |
| 2 | **Do we own it?** | **Fail as written** | See §1. The AWS-native stack in v2 is a vendor-locked control plane with no exit path — and I framed the sovereignty argument backwards. |
| 3 | **Is it simple?** | **At risk** | The board sprawl is being cut, good. But the "event-driven AI" layer is solving a throughput problem you don't have. See §3. |
| 4 | **Is it resilient?** | **Partial** | Degradation tiers are genuinely good. Two failure modes are unhandled, and one of them is the exact sin you're criticising WREMO for. See §4 and §5. |
| 5 | **Is it documented?** | **Fail** | Nothing planned. This is a 20-minute fix that doubles as a pitch slide. See §7. |
| 6 | **Tested at scale?** | **Fail — and this is the big one** | Ingesting 2 CRPs and claiming 125 is scaling by assumption. It's also unnecessary. See §6. |
| 7 | **Benefits the ecosystem?** | **Pass** | Open source, positive-sum, procurement bypass. One boundary to get right — see §8. |

---

## 1. The sovereignty inversion — I had this backwards

In v2 I recommended running the demo on a hosted model with the Mac Mini as a closing flourish. Judged against Omega's second principle, that's the wrong way round, and I'll correct it.

For **emergency** infrastructure, local-first isn't a preference or a bit of theatre. It's the correct default posture, because the system's whole purpose is to function in the conditions where connectivity fails. A cloud-default architecture with a local fallback is a system that degrades in an emergency. A local-default architecture with cloud burst is a system that degrades when it's *quiet* — which is the right way for it to fail.

**Reframe the tiers accordingly:**

| Tier | Runs | When |
|---|---|---|
| **Default** | Local inference, in the building | Always. This is the baseline, not the fallback. |
| **Burst** | Hosted model | Heavier reasoning when the link is up and the load justifies it |
| **Degraded** | Cached last-known-good brief | Inference unavailable |
| **Floor** | Printed brief + the VHF already in the hub kit | Everything else is gone |

This is also a *better pitch*, not a concession. "Our baseline runs in the hall" is a stronger claim than "we have an offline mode." And it's honest at an AWS event: the architecture is model-agnostic and deploys to AWS at region scale, so nothing about it is anti-cloud — it just refuses to *require* cloud. Framed that way, no judge hears a snub; they hear an engineer who has thought about failure.

---

## 2. The stack needs an exit path

`EventBridge → Lambda → DynamoDB → Bedrock` is a clean AWS reference architecture and it fails Omega's portability test outright. Every one of those is a control plane you don't own, and DynamoDB in particular has no drop-in equivalent — it will quietly shape your data model until leaving becomes a rewrite.

**Portable equivalent, same effort, no lock-in:**

| Instead of | Use | Why |
|---|---|---|
| Lambda + EventBridge | Containers + scheduled job (cron / systemd timer) | Runs on ECS, on a VM, or on the Mac Mini. Same artefact. |
| DynamoDB | **Postgres + PostGIS** | You have inherently geospatial data — hub locations, river gauges, road closures, hazard extents. PostGIS does hub→gauge proximity joins natively. DynamoDB cannot, and you'd hand-roll it. |
| Bedrock (hardcoded) | Any **OpenAI-compatible endpoint**, set by config | Bedrock, Ollama, llama.cpp, vLLM — all interchangeable behind one interface. |
| S3 (SDK-coupled) | S3-compatible API | S3 in cloud, MinIO on-prem, same code. |

**Deliverable claim this unlocks:** *"Same container set. Deploy it to AWS for a region, or to a Mac Mini in a church hall. No code changes, one config file."* That is Omega's sovereignty principle stated as a product property — and it directly answers a judge asking "who runs this in five years?"

PostGIS is the highest-value swap on that list. Make it today; it will save you writing distance maths.

---

## 3. You're building for throughput you don't have

Run the numbers honestly: **127 hubs. A handful of significant events per day. Five feeds, the fastest updating every 30 seconds, most hourly.** That is a few thousand records a day at absolute peak.

The "event-driven AI" box on the whiteboard is architecture for a problem two orders of magnitude larger. Omega's rule is design for 10x — but 10x of small is still small, and a message bus here is cleverness where clarity is called for.

**The brain-dead-simple version, which is also the correct version:**

```
poll (cron) → normalise to CAP → store in Postgres → match to hub → reason → render
```

One loop. One table. No bus, no queue, no orchestrator. It fits on one slide, one person can hold it in their head, and it is *far* easier to demo at 4pm than a distributed system. If throughput ever becomes real, a queue drops in behind the poller without touching anything downstream — so you lose nothing by deferring it.

Cutting this saves you hours today and improves the architecture slide. That's the good kind of trade.

---

## 4. A system that alerts must be able to retract

GeoNet retracts earthquakes — two of the three M4+ records we pulled were `quality: "deleted"`. Filtering them on read (v2's advice) handles the *display*, but not the real problem: **once you've pushed a notification, you've made a claim, and you need to be able to un-make it.**

If the system texts 40 volunteers "M5.2 near Newtown, open the hub" and GeoNet then withdraws the event, silence is the worst possible response. Every alert needs a correlation key back to its source record, and a retraction path that pushes the correction down the same channel it used originally.

This is a real design requirement most teams never think of, it costs almost nothing to build (a source ID column and one code path), and it's a *superb* answer to the inevitable "what if the AI is wrong?" question:

> *"Wrong is a state we designed for. Every alert is keyed to its source record, and if that record is withdrawn, the correction goes down the same channel. The system can un-say things. Most can't."*

CAP has native support for this — `msgType: Cancel` and `Update`, with `references` pointing at the superseded message. Another dividend from adopting the standard rather than inventing a schema.

---

## 5. Don't commit the sin you're pitching against

Your money slide is a four-week-stale hand-typed banner. So the one unforgivable failure mode for this system is **displaying something stale as though it were current.** If a feed dies at 3am and the board still shows its last value at 9am with no marker, you've rebuilt WREMO's problem with better typography.

**Design rule — make it non-negotiable: every displayed fact carries its age.** Not in a tooltip. On the face of it. `River: rising · 14 min ago`. And when a feed's age exceeds its expected cadence, the tile degrades visibly and says so: `Road closures — last update 4 hours ago, feed may be down`.

If you build one thing from this review, build this. It is cheap, it is visible on stage, it is the credibility of the entire product, and it makes the demo *self-demonstrating*: you can kill a feed live and show the board being honest about it. That beat is worth more than any feature you'd cut to make room for it.

Justified by the sources themselves, too: Metlink reserves the right to change feed URLs **without notice**, and GWRC disclaims all liability for reliance on its data. You are building life-safety UX on feeds with no SLA. The honest response isn't to pretend otherwise — it's to surface it.

---

## 6. Ingest all 125 CRPs — reversing my own advice

v2 said ingest two and say 125. Under Omega's sixth gate that's scaling by assumption, and having now thought about the actual cost, it's also just unnecessary caution: **125 small PDFs of text extraction is minutes of compute, not hours of work.** They're on a common template, so one parser handles the set.

Doing the full ingest gets you four things a two-file sample cannot:

1. **The claim becomes true.** "We ingested every published community response plan in the Wellington region" — said without an asterisk.
2. **It's a genuine scale test.** Toy datasets hide the failures. The real set will expose template drift, OCR-hostile pages, missing sections.
3. **It generates a data-quality finding, which is a pitch asset.** We already know plan dates run from **August 2022 to July 2026**; one hub is closed for renovations with a **2019** plan; a filename is misspelt `Whitby-CPR`; two inconsistent URL directories are in live use; and ~2 of 127 hubs appear to have no published plan at all. Present that as a *regional readiness map* — "here are the plans that have gone stale" — and you've handed WREMO something genuinely useful that nobody currently has. That is the accountability leg of the original 4R whiteboard, delivered as a by-product.
4. **It makes the parser the reusable artefact** — the templated, config-driven thing that gets you to Auckland next, rather than a bespoke two-file hack.

**Scrape from the six area pages' actual `href`s, never by constructing URLs** — the inconsistent directories and the misspelt file will silently 404 a naive scraper, and you'd never notice which hubs went missing.

**Caveat worth stating plainly on the slide:** the CRPs are WREMO copyright, and the hub location dataset is CC BY-NC-ND. Ingesting all 125 for a demo is defensible; redistributing them is not. Which leads to §8.

---

## 7. Write the ADR today — it *is* the scale slide

Omega's standard is that documentation ships with the deliverable. Hackathons almost never do this, which is exactly why doing it will stand out.

You have four decisions worth recording, and each takes three sentences: decision, alternatives considered, consequences.

1. **Normalise to CAP** — rather than a bespoke schema. Consequence: adding a feed is an adapter; adding a country is adapters.
2. **Portable container runtime, Postgres/PostGIS, swappable inference** — rather than cloud-native services. Consequence: deploys to a region or to a hall; no exit cost.
3. **Local-first inference with cloud burst** — rather than cloud-default. Consequence: degrades when quiet, not when it matters.
4. **Provenance and age on every displayed fact; retraction via CAP `Cancel`** — rather than best-effort display. Consequence: the system can be wrong out loud.

Twenty minutes of writing, and it converts directly into your "how would this scale" answer — which the mentor explicitly told you to have. Documentation as pitch asset. Two birds.

---

## 8. The open-source boundary — engine yes, corpus no

Open-sourcing is right, and it's the procurement bypass. But be precise about what you're actually licensing, because getting this wrong in public would be embarrassing:

- **Open-source the engine** — adapters, CAP normaliser, matcher, board, the CRP parser. This is yours, MIT or Apache 2.0, fork it freely.
- **You cannot relicense the corpus.** WREMO's guides are © all rights reserved; the hub dataset is CC BY-NC-ND. The repo ships *ingestion instructions*, not ingested content — each CDEM group brings its own documents.

Stated well, that separation is the positive-sum story with teeth: *"The engine is a public good. The content stays with the agency that owns it and is accountable for it. Auckland forks the engine and points it at Auckland's guide."* That's sovereignty and ecosystem in one sentence — and it's a governance answer, which is the original problem the mayors raised.

---

## 9. The honest limit of a two-day artefact

Omega's quality gates — lab testing, scale testing, refined deployment, rollback — cannot be met by Sunday, and shouldn't be claimed. This matters more here than in most domains: a system that tells volunteers what to do in a life-safety situation is not a "move fast" candidate.

Say the limit out loud, because it reads as expertise rather than hedging:

> *"This is advisory, and the human decides. Before it could be authoritative it needs lab validation against historical events, scale testing across all 125 hubs, a deployment path with rollback, and a runbook for the day it's wrong. We've built the architecture to survive that process rather than something we'd have to throw away to pass it."*

That is the difference between a hackathon prototype and a hackathon prototype built by people who run infrastructure. It's also, in a room full of demos, an unusual and disarming thing to volunteer.

---

## Concrete changes to make in the pitch

| Slide / claim | Change to |
|---|---|
| Cloud-first with local fallback | **Local-first with cloud burst.** Reverse the tier table. |
| "AWS-native architecture" | "Portable containers — same artefact on AWS or a Mac Mini." |
| Event-driven pipeline diagram | One loop: poll → normalise → store → match → reason → render. |
| "Ingested 2 hub plans (125 available)" | **"Ingested all 125 published plans"** + the staleness finding as a bonus slide. |
| Silent data display | Age on every tile; visible degradation when a feed goes quiet. Kill a feed live on stage. |
| "What if the AI is wrong?" | "It can retract. CAP `Cancel`, keyed to the source record." |
| "We'll open source it" | "Engine open source; corpus stays with the agency that owns it." |
| No docs | Four-decision ADR, doubling as the scale slide. |

---

## Bottom line

**The architecture passes.** Adopting CAP instead of inventing a schema, config-driven org profiles, one adapter per CDEM group, playbook-as-memory — that is templated, portable, ecosystem-positive engineering that would survive a real Omega review.

**The delivery choices need three corrections**, none expensive: invert the sovereignty default, swap to a portable runtime with PostGIS, and stop building for throughput that doesn't exist.

**And the one gap that matters most isn't in the build — it's in the honesty of the display.** A system that criticises a stale banner must never show a stale number silently. Age on every fact. That single rule is the product's credibility, and it's an afternoon's work.

---

*Reviewed against Omega Networks engineering standards. All external facts verified 5–6 August 2026.*
