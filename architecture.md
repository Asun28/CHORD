# Architecture
**6 August 2026 · companion to scope-and-pitch-v4**

---

## 0. The shape in one paragraph

One self-contained node per Community Emergency Hub. Each node polls hazard feeds (directly, or via a relay — one config value), normalises everything to CAP, decides by **rule** whether a hazard matters to its hub, and uses a **model** only to explain the situation and to select and order tasks from WREMO's own playbook. It carries the whole regional corpus, so it can reason about neighbours and stand in for a neighbour's node. Every displayed fact carries its age. With the model switched off it still works. When the power goes, it prints.

---

## 1. Topology — one node per hub

**A node contains:** feed adapters · CAP normaliser · Postgres + PostGIS · the regional corpus (125 response plans + Hub Guide + role and task catalogue) · rule engine · inference client · board UI · print renderer.

**Feed source is configuration, not architecture:**

```
FEED_MODE = origin | relay
RELAY_URL = https://…            # when FEED_MODE=relay
```

`origin` for a single node and for the demo. `relay` when a region runs more than a handful of nodes — because 127 nodes polling GeoNet, GWRC, NZTA and MetService directly is ~4 req/s sustained against public services whose rate limits are **undocumented, therefore unguaranteed**. Same container either way; the relay is a later deployment decision, not a rewrite.

**Peering comes from the corpus.** Every CRP names four neighbouring hubs. Load those as `hub_neighbour` and a node can (a) answer questions about its neighbours' situation and (b) serve a neighbour's last-known-good state when that neighbour's node is down.

```
PEERS = derived from hub_neighbour        # no manual config
```

**Explicitly not in v1:** central aggregation, an EOC roll-up view, node-to-node write sync, authentication. All are v2 slides. Regional roll-up is the obvious next component and it reads better as a roadmap item than as a half-built feature.

---

## 2. The deterministic / generative boundary

The single most important decision here. Rules decide **that** something matters; the model decides **what to say about it**.

| Job | Implementation | Why |
|---|---|---|
| Parse feed payload → CAP | **Code** | Models must never parse GeoJSON. |
| Does this hazard affect hub X? | **Rules** (PostGIS + thresholds + trust tier) | Must be explainable, testable, and identical on every run. |
| Posture: green / watch / act / respond | **Rules** | Same. This is the trigger; triggers must be deterministic. |
| Which tasks, in what order | **Model, selecting from a fixed catalogue** | Judgement, but bounded — see §6. |
| Situation summary in prose | **Model** | Language is the model's actual job. |
| Answer a volunteer's question | **Model + retrieval** | Ditto. |
| Suggest a role from quiz answers | **Model, constrained to 8 codes** | Fit judgement, hard-bounded output. |

**Design rule: the board must render correctly with inference disabled.** Posture from rules, tasks from the catalogue, facts from the database. Switching the model off costs you the prose and the ordering — not the function. That makes local inference an enhancement rather than a dependency, and makes the degraded tier a thing you can test rather than a thing you claim.

---

## 3. Data model

```sql
-- SOURCES AND OBSERVATIONS ------------------------------------------------
source(id, name, trust_tier CHECK IN (0,1,2,3), endpoint, format,
       cadence_s, licence, attribution)

observation(id, source_id, external_id, msg_type,        -- alert|update|cancel
            observed_at, fetched_at, expires_at,
            cap jsonb,                                    -- normalised CAP payload
            geom geography, severity, urgency, certainty,
            quality, superseded_by REFERENCES observation(id))
-- external_id + source_id is UNIQUE: re-fetch updates in place, never duplicates.

-- THE HUB AND ITS PLAN ---------------------------------------------------
hub(id, name, ta_name, address, geom geography,
    crp_url, crp_reviewed_on, kit_contents jsonb)
hub_neighbour(hub_id, neighbour_hub_id)
hub_asset(hub_id, kind, name, geom,
          sensitivity CHECK IN ('public','restricted'))   -- see §8
hub_gauge(hub_id, source_id, external_id, distance_m)     -- precomputed nearest gauges

-- THE PLAYBOOK -----------------------------------------------------------
role(code, name, description, priority_rank, source_ref)  -- 8 roles, 1–4 are priority
task_template(id, role_code, phase, text, source_ref)     -- phase: access|team|setup|
                                                          -- before_open|response|recovery

-- DERIVED STATE ----------------------------------------------------------
situation(hub_id, computed_at, posture, drivers jsonb)     -- current, one row per hub
situation_event(id, hub_id, at, from_posture, to_posture, driver_observation_ids)

-- THE ROOM ---------------------------------------------------------------
session(id, hub_id, opened_at, opened_by)
assignment(id, session_id, person_name, role_code, assigned_at, rationale)
task(id, session_id, template_id, assignee_id, status, created_at,
     reason, source_refs)
```

`source_ref` on every role and task points back to a page in the Hub Guide. That column is what lets the UI show "WREMO Hub Guide, p.12" next to every instruction — and it's why the system cannot present an instruction it didn't get from WREMO.

---

## 4. The pipeline, and the time cursor

```
poll → normalise to CAP → upsert observation → recompute situation
     → emit situation_event on posture change → render / notify
```

One scheduled loop. No message bus: 127 hubs and a handful of events a day is not a throughput problem, and a queue drops in behind the poller later without touching anything downstream.

**Build replay as the primary path.** Every read is scoped by a cursor:

```
now()  →  cursor        # "live" is simply cursor = now
```

Because `observation` stores `observed_at` separately from `fetched_at`, replaying a real past storm is just moving the cursor across stored rows. Three payoffs from one decision: a demo that behaves identically every run, the ability to replay historical events, and an honest answer to "how would you validate this?" — the replay harness *is* the validation harness.

---

## 5. Matching rules — explicit and testable

```
SPATIAL
  quake        ST_DWithin(obs.geom, hub.geom, radius(mmi))
  weather      ST_Intersects(obs.geom, hub.geom)      -- CAP area polygon
  road event   ST_DWithin(obs.geom, hub.geom, 5000)
  river gauge  hub_gauge mapping (precomputed), not distance at query time

TRUST
  P0 / P1      may raise posture alone
  P2           requires ≥2 independent sources within 60 min
  P3           annotates only — never raises posture, never generates a task

QUALITY
  exclude      GeoNet quality = 'deleted'
  supersede    CAP msg_type = 'cancel' → set superseded_by, re-run situation
  stale        observed_at older than source.cadence_s × 3 → tile degrades (§7)

POSTURE
  green    nothing matching
  watch    P0/P1 advisory, or P2 corroborated
  act      warning affecting the hub's area
  respond  hub-relevant event requiring hub activation
```

Write these as a table you can point at on stage. "Our thresholds are code you can read" is a strong answer in a room full of black boxes.

---

## 6. Model contracts — four narrow calls, structured output only

**1 · summarise_situation**
`in:` drivers[] (observations), hub facts → `out:` `{headline, prose, citations[]}`
Citations are observation IDs. No claim without one.

**2 · select_tasks**
`in:` posture, roles_present[], hub facts, relevant guide chunks
`out:` `[{template_id, assignee_role, order, reason}]`
**Returns template IDs, never text.** The model chooses and orders from WREMO's catalogue; it cannot author an instruction. This is the real answer to "what if it hallucinates" — not provenance, but structural incapability:

> *"The AI doesn't write emergency instructions. It selects from WREMO's official playbook and explains its ordering. Every task on that screen traces to a page in the guide."*

**3 · answer_question**
`in:` question, retrieved prose chunks, hub facts (via structured lookup)
`out:` `{answer, citations[], unknowns[]}`
`unknowns` is required, not optional — the model must be able to say what it couldn't determine.

**4 · suggest_role**
`in:` 4–6 answers, unfilled_priority_roles[]
`out:` `{role_code, rationale, second_choice}`
Output constrained to the eight role codes. Deterministic pre-filter supplies which priority roles are unfilled; the model only judges fit.

---

## 7. Honesty mechanisms

**Age on the face of every fact.** `River: rising · 14 min ago`. Not a tooltip. When `observed_at` exceeds `cadence_s × 3` the tile degrades visibly: *"Road closures — last update 4h ago, feed may be down."* Justified by the sources themselves: Metlink reserves the right to change feed URLs without notice; GWRC disclaims liability for reliance on its data. You're building life-safety UX on feeds with no SLA, and the correct response is to show it.

This also makes the demo self-demonstrating: kill a feed on stage and the board tells the truth about itself. *"The system we're replacing was four weeks stale and never said a word."*

**Retraction.** Every notification records the observation IDs that caused it. When an observation is superseded or cancelled, corrections go down the same channel that carried the original. CAP gives this natively — `msgType: Cancel` / `Update` with `references`.

**The print view.** The floor tier renders the board — posture, roles, assignments, task lists, last-known state with timestamps — to one page of A4. The last thing a node does before it dies is print the board.

> *"We're not competing with pen and paper. We produce it."*

---

## 8. Privacy — two views, one URL

The CRPs name aged residential care facilities and social housing complexes. `hub_asset.sensitivity` gates them:

- **Board view** (default, anyone in the room): posture, feeds, roles, tasks, public assets. **No restricted locations.**
- **Coordinator view**: unlocks with a code that lives in the hub kit alongside the lanyards. Adds restricted assets and the welfare picture.

No accounts, no auth service — the hub is physically gated, you walked through the door. Twenty minutes to build, five seconds to demo, and it's the governance answer made visible rather than asserted.

---

## 9. Corpus build — extract facts, retrieve prose

The most avoidable mistake here would be dumping everything into a vector store. Two different kinds of content, two different treatments:

**Extract into tables** (queryable): hub name, address, coordinates, the four neighbouring hubs, kit contents, water tank and facility locations, named community groups and services, vulnerable-population sites, plan review date. You need to *query* these — "which hubs are within 2km of this gauge", "which of Newtown's neighbours are up" — and embeddings cannot answer that.

**Retrieve as prose** (RAG): the Hub Guide's six sections, role descriptions, and the procedural checklists.

**Scraping notes that will otherwise cost you an hour:** take `href`s from the six area pages — never construct URLs. WREMO uses two live directories (`/assets/Hub-Guides/` and `/assets/Hub-Guide-CRPs/`), one file is misspelt `Whitby-CPR`, Days Bay points at the Eastbourne PDF, and a naive scraper 404s silently — you'd never know which hubs went missing. Record `crp_reviewed_on` per plan; it's the staleness metric and an SDG indicator (v4 §3).

The extraction schema is the artefact that ports to Auckland. Treat it as a deliverable, not a side effect.

---

## 10. Stack

| Concern | Choice | Note |
|---|---|---|
| Runtime | Containers + scheduled job | One compose file. Runs on the Mac Mini or ECS unchanged. |
| Store | **Postgres + PostGIS** | Spatial matching is a native query, not hand-rolled distance maths. |
| Objects | S3-compatible API | S3 in cloud, MinIO local, same code. |
| Inference | Any OpenAI-compatible endpoint, by config | Bedrock, Ollama, llama.cpp, vLLM — interchangeable. |
| UI | Server-rendered | No SPA. A board that reloads is fine and it's one less thing to break at 3pm. |
| Map | Simple pins on a regional map | Do **not** spend an hour on LINZ basemap API keys. |

---

## 11. Build order

1. **Corpus** — scrape and parse 125 CRPs + Hub Guide → extract → DB. Produces the staleness numbers.
2. **Adapters + fixtures** — five feeds, captured to disk while they're reachable. Both CAP feeds are empty right now, so fixtures are mandatory, not optional.
3. **Rules** — matching and posture. Testable, no model involved.
4. **Board** — with age badges from the first commit, not retrofitted.
5. **Contracts 1 and 2** — summary and task selection.
6. **Door flow** — quiz (4–6 questions) → role assignment → task list. This is the money-shot beat.
7. **Contract 3** — Q&A, if time.
8. **Local inference swap** — overnight. Pre-bake the prompt so it can't embarrass you.
9. **Print view** — last, cheap, and it closes the paper argument.

**Skip:** authentication, basemaps, chat, asset tracking, notification channels beyond one. The brief permits clickable or hi-fidelity screens — so anything unfinished at 11:30 becomes a screenshot rather than a debugging session.

---

## 12. Failure modes

| Fails | Behaviour |
|---|---|
| One feed down | Last-known-good, age badge, tile visibly degraded |
| Feed retracts a record | Supersede, recompute posture, push correction down the same channel |
| **Model unavailable** | **Board still works** — rules and catalogue are deterministic. Lose prose and ordering only. |
| Uplink down | Local inference; feeds go stale and say so |
| Node down | A neighbour node serves its last-known-good state — peers from the CRP data |
| Power down | Printed board from the last render |
| Everything down | The VHF radio already in the hub kit |

---

## 13. Decision record

**ADR-001 · Normalise everything to CAP.** *Alternatives:* bespoke schema, per-feed models. *Consequence:* adding a feed is an adapter, adding a country is adapters; NEMA's feed becomes config the day its URL is published; retraction semantics come free.

**ADR-002 · One self-contained node per hub; feed source configurable.** *Alternatives:* central SaaS, regional service + thin clients. *Consequence:* survives the loss of connectivity, which is the condition the product exists for. Accepts that direct polling doesn't scale past a handful of nodes, and answers that with `FEED_MODE=relay` rather than a second component.

**ADR-003 · Deterministic trigger, generative guidance.** *Alternatives:* model decides severity and relevance. *Consequence:* posture is explainable and reproducible; the board functions with inference disabled; the model is confined to language and ordering.

**ADR-004 · Extract structured facts, retrieve only prose.** *Alternatives:* embed the whole corpus. *Consequence:* spatial and relational questions are answerable; the extraction schema becomes the portability artefact.

**ADR-005 · Tasks are selected from an authoritative catalogue, never authored.** *Alternatives:* free-text task generation. *Consequence:* the system is structurally incapable of inventing an emergency instruction; every task traces to a page in WREMO's guide.

**ADR-006 · Age and provenance on every displayed fact; retraction via CAP Cancel.** *Alternatives:* best-effort display. *Consequence:* the system cannot silently repeat the failure it exists to fix, and it can be wrong out loud.

**ADR-007 · Local-first inference behind a swappable endpoint.** *Alternatives:* hosted-only. *Consequence:* degrades when quiet rather than when it matters; identical containers run on AWS at region scale.

**ADR-008 · Demo node runtime is native Swift (SwiftUI + MapKit + SwiftData).** *Alternatives:* containers + Postgres/PostGIS + server-rendered board (§10). *Consequence:* the logical architecture (CAP, rules, contracts, honesty mechanisms) is unchanged; the Mac Mini / hall-laptop node is a first-class implementation. PostGIS spatial matching is replaced by pure Swift distance / point-in-polygon for 125 hubs. A later regional deploy can re-home the store on Postgres without rewriting adapters or model contracts. Implementation lives in `HubNode/`.

---

*Companion to scope-and-pitch-v4. External facts verified 5–6 August 2026.*
