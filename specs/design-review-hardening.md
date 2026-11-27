---
slug: design-review-hardening
title: Close CHORD's broken guarantees and port the hub node to a Cloudflare web runtime
intent: intent/design-review-hardening.md
status: draft
created: 2026-11-26T11:00:00Z
skills_applied: [grilling]
---

# Spec: Close CHORD's broken guarantees and port the hub node to a Cloudflare web runtime
From intent: intent/design-review-hardening.md. Status: draft. Skills applied: grilling (Q1 to Q4 settled with the owner).

## Design review summary (Claude + Codex, 2026-11-26)

| Guarantee | Verdict | Evidence |
|---|---|---|
| Posture rules-only (ADR-003) | holds, rules weak | `Rules/PostureEngine.swift:41`; unrelated P2 reports corroborate (`:136`); area-less weather matches every hub (`SpatialMatch.swift:37`) |
| Tasks catalogue-only (ADR-005) | holds native, broken Companion | `DoorFlowService.swift:86` vs `WebUI/companion-console.html:388` |
| Model off still works | holds | `AskService.swift:73,159`; `CompositeInferenceClient.swift:190` |
| Age on every fact (ADR-006) | partial | web view drops stale flag (`HubNodeAPIService.swift:131`); feed pause lost on refresh (`AppModel.swift:198,226`, `PollLoop.swift:12`) |
| Retraction via CAP Cancel | partial | Update refs ignored (`DomainModels.swift:254`); replay reads present `isActive` (`ObservationStore.swift:46`) |
| Privacy gate (arch section 8) | broken | 940 restricted rows tracked (`Resources/Corpus/assets.csv`, `out/assets.csv`); HTTP Ask inherits global unlock (`AppModel.swift:301`, `HubNodeAPIService.swift:442`); `?contacts=1` and raw seed routes ungated; wildcard CORS; `HUBKIT` literal |
| Engine open, corpus closed (Omega section 8) | broken | WREMO PDF, 114 CRP texts, guide and plan chunks tracked under `out/` and `Resources/Corpus/`; no LICENSE |
| Local-first (ADR-002, ADR-007) | partial | print unbuilt (`FEATURES.md:168`) |
| Docs agree | broken | 127 vs 125/114 hubs; findings section 5 stale; PRD auth/EOC token vs arch "no auth v1"; Pages promises print |

## Requirements (EARS)
Revised after the Codex plan review of 2026-11-26.
- R1. The repository shall contain, at HEAD of `Asun28/CHORD` only, no restricted asset row and no file derived from the WREMO or GWRC corpus (hubs, assets, roles, task templates, neighbours, staleness, guide and plan text, PDFs), per a committed inventory; git history is not rewritten.
- R2. WHEN the corpus tools run, the corpus build shall write its outputs only under a gitignored `corpus/` directory.
- R3. The repository shall carry a fictional demo corpus, labelled fictional on every screen that shows it, that the web node loads when no real corpus is present.
- R4. IF a request carries no valid coordinator session, THEN the web node shall return no restricted asset in any page or API response, and shall send `Cache-Control: private, no-store` on every response that varies by view.
- R5. WHEN a coordinator unlocks, the web node shall grant coordinator view to that browser session only: HMAC-signed HttpOnly SameSite=Strict cookie (Secure outside localhost), 30-minute expiry, logout, at most 5 failed attempts per 15 minutes, and an Origin check on every state-changing request.
- R6. The web node shall derive posture from rules only; a P2 observation shall raise posture only with a second independent source for the same hazard type and overlapping area within 60 minutes.
- R7. IF an observation has no area geometry, THEN the matcher shall not treat it as affecting every hub.
- R8. The store shall identify a message by (source, CAP identifier), ignore a re-fetch of a known message, and WHEN a Cancel or Update references an earlier message, supersede it from the referencing message's sent time, including a reference that arrives before its target; a replay cursor before that time still shows the original.
- R9. WHILE a feed is paused, the web node shall keep it paused across refreshes, replay steps and restarts until it is resumed; pause and resume require a coordinator session.
- R10. The board shall show, for every displayed fact, its observation age at the cursor and its feed's last fetch time, and mark a fact stale when its age exceeds three times its source cadence; IF the store cannot be read, THEN the board shall show an error state and never a green posture.
- R11. The web node shall expose no Ask, contacts or raw seed route.
- R12. The board shall render a print view of one A4 page: posture, roles, tasks, public assets, each fact with its timestamp, and the render time; restricted assets never print.
- R13. WHEN the hall laptop has no network, the web node started from an initialised local D1 shall serve the board, replay and unlock, and keep its state across a restart.
- R14. The design documents shall state one runtime decision (ADR-010, including that local cron does not run automatically and hall polling is manual fixture stepping), ADR-005 binding on every surface, one set of hub counts, an engine licence, and a capability matrix.

## Design
- Runtime (ADR-010, supersedes ADR-008): Next.js 16 App Router in `node/`,
  run on Cloudflare Workers through vinext; D1 for observations, situation,
  feed state and the corpus; a Cron Trigger runs the poll loop; secrets via
  `wrangler secret`. Hall mode: the same Worker runs on a laptop with
  `wrangler dev` and local D1, so "same artefact in the cloud or the hall"
  stays true. Deploying to Cloudflare is a release step outside this goal.
- Layers: `node/src/lib/` pure TypeScript (contracts, CAP, rules, view
  model) with no Cloudflare import, tested by `node --test`;
  `node/src/server/` D1 access and session; `node/src/app/` pages and
  route handlers.
- Data: real corpus loaded into D1 by a local import from `corpus/`; the
  fictional fixture is loaded when D1 has no corpus.
- HubNode stays in the repo, frozen, with a known-issues notice.

## Interfaces and contracts
- Frozen: `node/src/lib/contracts.ts` (CapAlert, Observation, TrustTier,
  Posture, Hub, Asset with sensitivity, Role, TaskTemplate with
  source_ref, ViewMode, Situation) and `node/migrations/0001_init.sql`.
- `POST /api/unlock` {code} -> 303 to `/` + session cookie, or 401; `POST /api/lock`.
- `GET /` board for the home hub; `GET /hub/[id]` board for any hub;
  query `at=<ISO>` sets the replay cursor.

## Data model and migration impact
New D1 schema from architecture section 3 (source, observation with
`superseded_by` and `superseded_at`, hub, hub_neighbour, hub_asset,
role, task_template, situation, feed_state, unlock_attempt). Greenfield;
no existing data to migrate.

## Flagged concerns (route to policy owners)
- Git history of `Asun28/CHORD` and upstream `joshuatj/ai-hackathon-2026`
  still holds the restricted rows and WREMO content. Purge needs an owner
  decision (force push) and an upstream request.
- WREMO and GWRC permission for any hosted deploy using the real corpus.

## Non-goals
- Ask (Kea) and its fixed refusal, door flow, browser offline cache,
  live feed adapters, automatic hall polling, regional map, neighbours
  panel, Companion console port, Cloudflare deploy: next goal. Cloud-only
  clients lose access when the uplink fails; the docs say so.
- Any Swift change; the legacy HubNode build and runtime are unsupported
  after corpus removal.
- Accounts or multi-user auth beyond the coordinator code.

## Acceptance
- 1. A guard script, checked against a committed inventory, fails on any tracked restricted row or corpus-derived file and passes at HEAD. [R1][R2]
- 2. The web node builds on Windows and its board renders from the labelled fictional corpus. [R3]
- 3. Integration tests with two cookie jars show public responses free of restricted names, per-session unlock, expiry, logout, attempt limit, Origin rejection and no Ask, contacts or seed route. [R4][R5][R9][R11]
- 4. Rule and D1 store tests cover P2 corroboration, area-less alerts, message identity, re-fetch, Cancel and Update (including out of order) at a replay cursor, pause across restart, staleness and the store-error state. [R6][R7][R8][R9][R10]
- 5. A Windows script starts the node with the network off, checks board, replay and unlock, restarts and checks again; the print view test finds no restricted name. [R12][R13]
- 6. architecture.md holds ADR-010; docs agree on counts, the task rule, the licence and the capability matrix (reviewer-verified). [R14]
