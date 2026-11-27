# Capabilities: what each guarantee does today

Each row is a guarantee from the design review table in
`specs/design-review-hardening.md`. Verdicts are **holds**, **partial** or
**broken**, rated against `main` at d82aee9 (T1-CORPUS-OUT-OF-REPO,
T1-NODE-SCAFFOLD and T1-NODE-RULES-REPLAY merged). Paths under HubNode are
relative to `HubNode/HubNode/`. "Closes" names the card or goal that fixes a
gap. Update a row in the same change that alters the behaviour it describes.

## HubNode (legacy, frozen)

HubNode receives no fixes; its gaps stay open. See the legacy notice in
`HubNode/README.md`.

| Guarantee | Verdict | Evidence |
|---|---|---|
| Posture rules-only (ADR-003) | holds, rules weak | No model call decides posture (`Rules/PostureEngine.swift:41`), but unrelated P2 reports corroborate each other (`:136`) and weather with no area matches every hub (`SpatialMatch.swift:37`). |
| Tasks catalogue-only (ADR-005) | holds native, broken Companion | Door flow selects catalogue templates (`DoorFlowService.swift:86`). The bundled Companion console drafts task details (`Resources/WebUI/companion-console.html:388`); ADR-005 now binds that surface too and the PRD cuts the feature, but the frozen console is not changed. |
| Model off still works | holds | `AskService.swift:73,159`; `CompositeInferenceClient.swift:190`. |
| Age on every fact (ADR-006) | partial | The web view drops the stale flag (`HubNodeAPIService.swift:131`); feed pause is lost on refresh (`AppModel.swift:198,226`, `PollLoop.swift:12`). |
| Retraction via CAP Cancel | partial | Update references are ignored (`DomainModels.swift:254`); replay reads the present `isActive` (`ObservationStore.swift:46`). No notification channel exists. |
| Privacy gate (architecture section 8) | broken | One unlock serves every HTTP client (`AppModel.swift:301`, `HubNodeAPIService.swift:442`); `?contacts=1` and raw seed routes are ungated; wildcard CORS; `HUBKIT` literal (`AppModel.swift:50`). The 940 restricted rows left HEAD with T1-CORPUS-OUT-OF-REPO but stay in git history. |
| Engine open, corpus closed | partial | Corpus files left HEAD (`tools/corpus-inventory.txt`, guard `tools/check_published.py`); git history and forks still hold them (owner decision on a purge). Engine licence: `LICENSE`. |
| Local-first (ADR-002, ADR-007) | partial | Runs offline on a Mac, but the print view is unbuilt (`HubNode/FEATURES.md`, "Print / A4 board"), and the app cannot start from a fresh checkout because its corpus is gone. |

## Web node (`node/`, ADR-010)

| Guarantee | Verdict | Evidence | Closes |
|---|---|---|---|
| Posture rules-only (ADR-003) | partial | Rules hold: no model call; a P2 report needs a second source, same hazard, within 60 minutes; an alert with no area matches no hub; a store error gives posture `error`, never green (`node/src/lib/rules.ts`, `node/src/lib/rules.test.ts`). The board does not show posture yet (`node/src/lib/board.ts` renders the hub name and the fictional label only). | T1-NODE-HALL-PRINT |
| Tasks catalogue-only (ADR-005) | holds | No route or page writes task text; the only route is `POST /api/fixtures/step`. Every template carries a role code and a `source_ref` (`node/src/lib/fixture.test.ts`). The board shows no tasks yet. | |
| Model off still works | holds | The node calls no model: there is no inference client in `node/src`. Ask is out of scope for this goal. | |
| Age on every fact (ADR-006) | partial | The store records sent and fetch times per message (`node/src/server/store.ts`, `activeAt`), and feed pause persists across a restart (`node/src/server/store.test.ts`). The board shows no fact, age, fetch time or stale state yet. | T1-NODE-HALL-PRINT |
| Retraction via CAP Cancel | holds | Messages are keyed by (source, CAP identifier); a re-fetch changes nothing; Cancel and Update supersede from the referencing message's sent time, in any arrival order, and a replay cursor before that time still shows the original (`node/src/server/store.test.ts`). No notification channel exists; that is next goal. | |
| Privacy gate (architecture section 8) | partial | No response contains any asset, public or restricted: the board reads only the hub name (`node/src/lib/board.ts`), and there is no Ask, contacts or seed route. There is no coordinator session yet, `POST /api/fixtures/step` is open to any client (`node/src/app/api/fixtures/step/route.ts`), and no response sets `Cache-Control: private, no-store`. | T1-NODE-VIEW-GATE |
| Engine open, corpus closed | holds | The node ships only the fictional corpus (`node/fixtures/demo-corpus.json`), labelled "Fictional demo data" on the board. Engine licence: `LICENSE`. | |
| Local-first (ADR-002, ADR-007) | partial | The built Worker serves the board from local D1 under `wrangler dev` (`node/SPIKE.md`). Local cron does not run on its own, so hall polling is manual fixture stepping. No print view and no offline restart check exist yet. A client that reaches only the cloud deployment loses access when the uplink fails. | T1-NODE-HALL-PRINT |

## Documents

| Guarantee | Verdict | Evidence |
|---|---|---|
| Docs agree | holds | One runtime decision (ADR-010), ADR-005 on every surface, 125 hubs (114 with a published plan, 11 without), engine licence and this matrix. `python tools/check_docs.py` checks ADR-010, dashes and the old hub count. |
