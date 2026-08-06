# What was built — Hub Companion demo

**One file:** `Hub Companion Demo.dc.html` · Wellington Region, NZ · fictional M7.1 Wellington Fault scenario, 14 Aug 2026
Grounded in the *Wellington Region Community Emergency Hub Guide* (WREMO, July 2025) and the WCC website design system.

---

## The idea in one line

Digitise the Hub Guide's paper artifacts exactly as designed — Situation Board, Needs and Offers, roster, status report — so a hub with power runs faster, and a hub without one loses nothing. The platform is an accelerant with a paper fallback, never a dependency.

---

## Eleven screens

| Screen | What it does |
|---|---|
| **My shift** | Your role's runbook as a tickable checklist, your jobs urgent-first with how/when/where and a WREMO page reference, unassigned jobs for your role only, what you finished, and the constraints before you go out |
| **Situation** | Guide-exact board as disclosure rows with Official / Hub-verified / Unconfirmed provenance; filters; verify-and-stamp on unconfirmed rows; the cascade of one quake into six incidents |
| **Needs & offers** | Guide-mandated fields, life-threatening hard route, role-gated contacts, rule-filtered candidates plus Kea's ranked suggestions, outcome note required, channel-ready sharing |
| **Roles, roster & tasks** | Eight roles across two shifts, several people per role, double-hat flags, loud unfilled state, role-scoped task board, AI-drafted task details, handover digest |
| **Live monitor** | Leaflet map with eight toggleable feed layers, severity filters, hover popups, synced list, per-feed status and licence |
| **Status report** | Compiles from live board state into the guide's structure plus a slow-read radio script; prints A4 |
| **Public info** | The wall board, official messages relayed verbatim, large-print toggle |
| **Am I impacted?** | Deterministic zone checker — four demo points including a boundary case and an offline case; natural-warning rule always primary |
| **Ask Kea** | The assistant (see below) |
| **Records** | Roster, VHF message log, decisions, and the constraints the guide says to keep repeating |
| **Settings** | Every data connection in and out, the redaction rule, Kea's model configuration, the EOC API token |

---

## Kea — the assistant

A floating agent in the bottom-right corner of every screen.

- **Two sources, one floor.** On-device retrieval over the Hub Guide corpus, or an online model — built-in, or your own OpenAI-compatible endpoint (Ollama, llama.cpp, hosted) with model and key fields and a connection test. If the model is unreachable, the question is still answered on the device and Kea says so.
- **Live feeds too.** "Latest quakes", "any weather warnings", "power and water" read the monitor items back with times and fetch state, attributed. Guide-phrased questions always route to the guide, so a feed can never swallow a safety answer.
- **A citation on every answer** — a Hub Guide page, or the feeds it relayed from.
- **Fixed refusal** for personal-safety questions: the natural-warning rule, the checker, official channels, 111. It never reasons about "should we evacuate".
- **Turn an answer into a task** — drafts steps, timing, guide reference, a suggested role and a suggested person, all editable. It cannot assign anyone; confirming stamps the confirmer's name.
- **Voice input** in the selected language, transcribed into the box to read before sending.
- **Source count** visible: how many data sources are connected, and which.

---

## Where AI helps, and where it is refused

**Helps:** ranking match candidates with reasons written out; drafting task instructions and the handover digest; converting an answer into an assignable task; suggesting a role and a person.

**Refused, structurally:** no model in the hazard-zone path; no evacuation advice; no suggestion of life-threatening needs for matching; no agent can assign a task, commit a volunteer, alter the roster, clear a need or close the Hub. Everything AI produces is labelled a suggestion and needs a named person to confirm.

---

## Data

**In:** GeoNet quakes · MetService CAP warnings · NEMA alerts · Wellington Water faults · electricity outages · NZTA road status · this hub's own reports · the community hubs layer. Each shows its endpoint, licence, poll interval and last fetch, and can be switched off.

**Out:** REST API, A2A agent card, MCP server, file exports — all reading **one redacted view**. Names, phone numbers and house numbers are stripped; streets, categories and counts travel. Turning redaction off requires the Hub Supervisor.

---

## Languages

English · Te Reo Māori · Gagana Sāmoa · 简体中文 · हिन्दी.

Translated: tab labels, screen headings, task states, priority, role badges, the How/When/Where/Check-against labels, main buttons, the natural-warning rule, the life-threatening banner, hub status, the 111 line, and Kea's launcher.

Not translated on purpose: board entries, task instructions and guide passages — with a persistent strip saying so in the reader's language. The instruction travels first, the detail follows.

---

## Design decisions worth defending

- **The paper is the design system.** Where the screen and the guide disagree, the guide wins — it is what is in the kit when the power is out.
- **Provenance is colour *and* a dot *and* a label**, everywhere including print, so it survives a monochrome screen in bright sun.
- **Unassigned and unfilled are loud red states.** Unassigned work is the most dangerous state in a response.
- **Symbols and words over icon libraries.** No icon font, no webfont on response surfaces — system fonts and inline SVG only.
- **Degrade honestly.** Offline mode says what is cached and how old it is; no spinner where a fallback belongs.
- **Mobile-first.** Fluid wrapping layouts, `clamp()` type, 44px targets, a sticky header of only a status strip and tabs, no fixed columns.
- **Every task carries a WREMO reference** so a volunteer can verify it against the printed guide or wremo.nz.

---

## Honest limits

- Translations are machine-drafted and need native-speaker review; te reo Māori needs WREMO and mana whenua engagement.
- WREMO page references in the tasks and corpus must be checked against the printed July 2025 guide.
- Checker zone classes are demo placeholders — verify against the live WCC layer.
- The hubs layer is CC BY-NC-ND 4.0: demo with attribution is fine; launch needs permission or an independent dataset.
- The basemap and the online model are tier-2 only; the low-bandwidth surface makes no third-party requests.
- All people, phone numbers and street numbers are fictional. Real information: civildefence.govt.nz · geonet.org.nz · wremo.nz · 111.
