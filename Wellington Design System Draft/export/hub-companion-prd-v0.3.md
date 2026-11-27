# PRD: Hub Companion v0.3 (as built)
**Community Emergency Hub coordination platform, Wellington Region NZ**
7 Aug 2026 · Impact Lab hackathon build · Canonical workflow source: *Wellington Region Community Emergency Hub Guide*, WREMO, July 2025

**What changed from v0.2:** v0.2 was a plan. v0.3 describes the working demo: ten screens in one console, an assistant named Kea with a switchable on-device / online model, five-language chrome, rule-plus-Kea matching for needs and offers, role-scoped task lists with WREMO page references, a live multi-feed monitor map, and a settings screen showing every data connection. All demo data is fictional.

---

## 1. Problem

125 volunteer-run Community Emergency Hubs (114 with a published response plan, 11 without) coordinate their communities when official services are overwhelmed. A hub runs on paper: Situation Board, Public Information Board, Needs and Offers boards, a message log and a VHF radio to the EOC. That is deliberately resilient, but it cannot be searched, shared between hubs, carried across a shift change, or seen by the EOC until someone reads it over the radio. Residents have no self-service way to answer "am I in a tsunami zone and where is my nearest hub".

**Thesis:** digitise the Hub Guide's artifacts exactly as designed: never replace them. A hub with power runs faster; a hub with neither power nor signal runs on paper exactly as WREMO trained it.

## 2. Guardrails (unchanged, and visible in the build)

| # | Principle | How the build honours it |
|---|---|---|
| GP1 | Paper parity | Every screen prints; chrome and controls are marked `data-noprint` |
| GP2 | Official sources only for life safety | Checker uses cached official zone layers; verbatim instruction text; no model in that path |
| GP3 | Provenance on everything | Official / Hub-verified / Unconfirmed shown as colour **and** dot **and** label, including in print |
| GP4 | Suggest, don't decide | Kea proposes catalogue task IDs and match candidates; a named person confirms; the confirmation is stamped. Kea never drafts task text (ADR-005) |
| GP5 | Hub ≠ authority | "Community-run: not an official CDEM channel" in the header, on shares, and on public copy |
| GP6 | Degrade gracefully | Offline toggle: cached feeds, no tiles, on-device answers, queued writes |
| GP7 | Data minimisation | Contacts role-gated; one redaction rule for every export channel |

## 3. What is built: screen by screen

### 3.1 My shift (default screen)
One question per screen: what am I doing now. Shows the role(s) you hold this shift, your **runbook** from the guide as a tickable checklist, your jobs ordered urgent-first then by time, unassigned jobs **for your role only**, what you finished, and the "before you go out" constraints. Jobs can be updated in place: status, priority, and the what/how/when/where details.

### 3.2 Situation Board
Guide-exact columns as disclosure rows: time, place, what is happening, our response, priority. Filters: All / Urgent / Unconfirmed / Not completed. An unconfirmed row carries a verification task; "Mark hub-verified" stamps your name and the time. Below it, the cascade view: one earthquake, six knock-on incidents.

### 3.3 Needs and offers
Guide-mandated fields, life-threatening hard-route banner ("attempt 111 · inform EOC via Communications"), contact details visible to Needs and Offers and the Supervisor only.

**Matching is two-layer:**
- *Rule filter* (system of record): category → allowed offer categories, not exhausted, freshest first.
- *Kea suggestions* (advice): ranked Strong fit / Worth a call / Long shot with the reasoning written out, plus caveats a filter cannot express, such as "step-free access is not stated in this offer", "not a water offer, only useful for boiling". Life-threatening needs are never suggested. Confirming requires an outcome note.

**Sharing:** open needs and available offers compose channel-ready text for WhatsApp, Facebook, X, SMS or email, or copy to clipboard. Nothing auto-posts. The text always carries the community-hub footer and the 111 line, with names and phone numbers stripped. Welfare and life-threatening items refuse to share.

### 3.4 Roles, roster and tasks
Eight guide roles, two shifts. **A role can be held by several people** and one person can hold several roles; both states are shown, and double-hatting is flagged. Unfilled is loud and red. Each role card opens its runbook. The task board is **role-scoped by default** (chips switch to Assigned to me / Nobody assigned / Every role). Adding a task means choosing a catalogue task by ID; Kea may propose catalogue IDs, and a named person confirms each one. Kea drafting the how/when/where of a task is cut (ADR-005). Handover digest drafts from live board state and requires confirmation.

### 3.5 Live monitor
Leaflet map, eight toggleable feed layers (GeoNet, MetService, NEMA, Wellington Water, outages, NZTA, hub reports, community hubs layer), severity filters, hover and click popups, and a synced list. Feed status strip shows Live / Snapshot / Cached with fetch time and licence. Offline mode drops the basemap and marks everything cached. The map never issues a warning: it relays with attribution.

### 3.6 Status report
Compiles from current board state into the guide's structure plus a slow-read radio script with phonetic times. One tap prints A4 with the chrome removed.

### 3.7 Public Information Board · 3.8 Am I impacted? · 3.9 Ask Kea · 3.10 Records · 3.11 Settings
Public board with a large-print toggle. Checker: four demo points including a boundary case (rounds to the more severe zone) and an offline case, with the natural-warning rule always primary. Kea: see §4. Records: roster, VHF message log, decisions, and the constraints. Settings: see §5.

## 4. Kea: the assistant

Named plainly; a working title, like the product name. **Not** a public advice chatbot.

- **Two sources, one floor.** On device (Hub Guide + Community Response Plan corpus, deterministic keyword retrieval) or an online model. On-device is always the floor: if the endpoint fails, the question is still answered and Kea says where the answer came from.
- **Live feeds too.** Status questions ("latest quakes", "any weather warnings", "power and water") read the Live monitor items back with times and fetch state. Guide-phrased questions ("how do we…") always route to the guide, so the feed path can never swallow a safety answer.
- **Citations on every answer**: a Hub Guide page, or the feeds it relayed from.
- **Fixed refusal** for personal-safety questions: the natural-warning rule, the checker, official channels, 111. It never reasons about "should we evacuate".
- **Propose catalogue tasks**: from an answer, Kea may propose catalogue task IDs with a suggested role. It cannot write task text or assign anyone; a named person confirms each proposal, and the confirmation records the confirmer's name. Turning an answer into a newly drafted task is cut (ADR-005, architecture.md section 13).
- **Voice input** using the device's own speech recognition, in the selected language, transcribed into the box for you to read before sending.
- **Source count** is visible: how many data sources are connected, and which.

## 5. Settings: data flow and model connections

- **Coming in:** every feed with its endpoint, licence note, poll interval, last fetch and a connect/disconnect control.
- **Going out:** file exports, reading **the redacted view**. The REST API, A2A agent card and MCP server are v2, not this version: architecture.md section 1 rules out aggregation and authentication in v1.
- **Redaction table** is shown in full, and turning it off requires the Hub Supervisor role.
- **Model connection:** mode, provider (built-in or your own OpenAI-compatible endpoint: Ollama, llama.cpp, hosted), model, key, and a live connection test.
- **API access:** v2, not this version. This version has no bearer token and no EOC token.

## 6. Languages

English · Te Reo Māori · Gagana Sāmoa · 简体中文 · हिन्दी.

Translated: all tab labels and screen headings, task states, priority, role badges, the How/When/Where/Check-against labels, main action buttons, the natural-warning rule, the life-threatening banner, hub status and the 111 line.

Not translated, deliberately: board entries, task instructions and guide passages, with a persistent strip saying so in the reader's own language. Machine-translating hazard detail is not honest; the instruction travels first and the detail follows.

**Before deployment:** every string needs native-speaker review, and te reo Māori requires engagement with WREMO and mana whenua. Do not ship the current strings.

## 7. Degradation tiers

| Tier | Conditions | Surface |
|---|---|---|
| T0 | No power or devices | Paper. Pre-printed boards, role cards, message forms |
| T1 | Patchy signal, battery | Phone-first console, cached feeds, queued writes, on-device Kea |
| T2 | Power and connection | This console: map, settings, exports, online model |

The user picks the tier; it is never auto-detected. Every tier states which it is and links down. The Live monitor's basemap is the only tier-2-only element.

## 8. Non-goals

Not an alerting authority. Not a replacement for the radio, 111 or the EOC. Not a CIMS system for agencies. Not a social network. Not predictive. Not a vulnerable-persons register. No automated social posting. No turn-by-turn evacuation routing. No public advice chatbot.

## 9. Demo run sheet (~4 minutes)

1. **0:00 Framing.** "125 community hubs, paper boards, a VHF radio. We digitised the paper without replacing it." Hub Guide page beside the screen.
2. **0:20 My shift.** Sign in as Marcus (Needs and Offers). His runbook, his jobs, urgent first, each with how/when/where and a WREMO page to check it against.
3. **1:00 Needs and offers.** Kea's suggested matches; open the wheelchair one and read the caveat aloud. Confirm the chainsaw match with an outcome note.
4. **1:40 Life-threatening.** Open NEED-001: hard-route banner, sharing refused, already queued for the radio call to the EOC.
5. **2:10 Kea.** Ask "how do we treat drinking water" → guide answer with page. Ask "latest quakes" → feed answer with attribution. Ask "should the people on The Esplanade evacuate" → fixed refusal. Propose a catalogue task from one answer and confirm it by name.
6. **2:50 Status report.** Compiles live; show the radio script; print A4.
7. **3:20 Offline.** Toggle offline: basemap drops, feeds go cached, Kea keeps answering on device.
8. **3:40 Language.** Switch to 简体中文: chrome and the natural-warning rule translate, the untranslated note appears.
9. **3:50 Ask.** "We built it to WREMO's own guide. We want to test it in a WREMO hub practice exercise."

## 10. Open questions

1. Will WREMO engage after the event? Phase 1 assumes that conversation.
2. Hubs-layer licence is CC BY-NC-ND 4.0: permission or an independent dataset is needed before launch.
3. No published evidence a hub has fully activated in a real event; the exercise programme is the honest first venue.
4. Is there any sanctioned machine-readable hub→EOC channel besides voice radio?
5. Who owns the hub count and its future changes? This document uses 125 hubs, 114 with a published plan and 11 without (`verified-findings.md` section 1).
6. Hosting and stewardship after the hackathon.

## 11. Attribution and licences

GeoNet CC BY 3.0 NZ, supplied without warranty · MetService open CAP feed only · NEMA attributed, terms unstated · WCC and GWRC tsunami and flood layers, credit required, terms unstated · Community hubs layer CC BY-NC-ND 4.0 · Emergency routes require consulting WCC · LINZ CC BY 4.0 · WREMO Hub Guide © WREMO · Basemap © Esri and OpenStreetMap contributors.

**All demo content is fictional.** Real information: civildefence.govt.nz · geonet.org.nz · wremo.nz · 111 for emergencies.
