# HubNode. Built functions (test handoff)

**Repo:** `AWS AI Hackathon` · branch `main` 
**App:** `HubNode/HubNode.xcodeproj` · scheme **HubNode** · macOS 

Open: `open HubNode/HubNode.xcodeproj` → Run (⌘R).

Settings for the app: **HubNode → Settings…** (or macOS Settings when the app is focused).

**Design standard:** [`DESIGN.md`](DESIGN.md) (no em/en dashes in app copy). Run `scripts/check-no-emdash.sh` before push. Architecture: ADR-009 in `architecture.md`.

---

## How to read this sheet

| Column | Meaning |
|---|---|
| **Status** | Intended readiness for demo |
| **Where** | UI path or main code entry |
| **How it works** | Short behaviour notes |

**Status key:** 
✅ Ready to test · ⚠️ Partial / fixture-backed · 🔲 Not built / stub

---

## 1. Node identity (this hall)

| Function | Status | Where | How it works |
|---|---|---|---|
| **Set home hub** | ✅ | First launch screen; **Change hub** toolbar; Settings → This hub | Pick which of 125 CEHs this Mac serves. Persisted in `UserDefaults` (`NodeConfig`). Board defaults to that hub. |
| **Go home** | ✅ | Toolbar **Home**; map header **Back to your hub** | Selects home hub, leaves regional map mode. |
| **Coordinator unlock** | ✅ | Hub board toolbar **Unlock** | Code `HUBKIT` shows restricted assets. No accounts. Physical room gate (architecture §8). |

**Code:** `NodeConfig.swift`, `HomeHubSetupView.swift`, `AppModel.setHomeHub` / `goHome` / `unlockCoordinator`.

---

## 2. Corpus & data

| Function | Status | Where | How it works |
|---|---|---|---|
| **Load 125 hubs** | ✅ | App launch | `hubs.json` → `app.mapHubs` (value types for map). Fallback CSV if needed. |
| **SwiftData seed** | ✅ | After launch / reload | Hubs, assets, 8 roles, task catalogue, guide chunks into local store. |
| **Plan prose (CRP text)** | ✅ | Bundled `plan_chunks.jsonl` | Per-hub passages for Ask; loaded once via `PlanChunkStore`. |
| **Reload corpus** | ✅ | Settings → Reload corpus | Reseeds store from bundle. |
| **Attribution** | ✅ | Footer always | GWRC + WREMO on every main screen. |

**Code:** `CorpusBootstrap.swift`, `Resources/Corpus/*`, `tools/build_plan_chunks.py` (regen only).

---

## 3. Feeds → CAP → posture (deterministic)

| Function | Status | Where | How it works |
|---|---|---|---|
| **Fixture replay** | ⚠️ | Toolbar **Replay** scrubber / +1h / +4h | Scripted southerly, river, roads, quake. Not live NZ quiet day. |
| **Poll adapters** | ⚠️ | Toolbar **Refresh**; auto after bootstrap | `PollLoop` → CAP normalise → `Observation` upsert. Real Metlink/GeoNet adapters = teammate drop-in (`FeedAdapter`). |
| **Kill / pause a feed** | ✅ | Toolbar **Feeds** menu | Tile ages / degrades (honesty demo). |
| **Posture rules** | ✅ | Pin colour + board banner | green / watch / act / respond from trust + spatial + severity. **No model.** |
| **Age on facts** | ✅ | Situation tiles | Face age badges; stale when older than cadence × 3. |

**Code:** `FixtureFeedAdapter` / `DemoReplay`, `PollLoop`, `CAPNormaliser`, `PostureEngine`, `SituationService`, `ObservationStore`.

---

## 4. Hub board (ops UI)

| Function | Status | Where | How it works |
|---|---|---|---|
| **Situation banner** | ✅ | Top of hub board | Posture + optional model summary prose. |
| **Situation tiles** | ✅ | Board | Drivers matching this hub; degraded feeds called out. |
| **Roles strip** | ✅ | Board | 8 WREMO roles; P1-4 marked; filled vs unfilled from session. |
| **Tasks list** | ✅ | Board | Tasks created by walk-in (catalogue only). |
| **Public assets** | ✅ | Board | Water tanks, venues, places; sensitivity gated. |
| **Restricted assets** | ✅ | After coordinator unlock | Medical / ECE / aged care etc. |
| **Neighbours** | ✅ | Board list | Geometric k=4 (or seeded edges); tap opens that hub. |
| **Make this home** | ✅ | Toolbar when browsing another hub | Sets home to the hub you’re viewing. |

**Code:** `HubBoardView.swift`, `DoorFlowService` for session data.

---

## 5. Walk-in / door flow

| Function | Status | Where | How it works |
|---|---|---|---|
| **Walk-in quiz** | ✅ | Board toolbar **Walk-in** | **First + last name** + short questions. |
| **Priority roles first** | ✅ | Assignment logic | Unfilled P1-4 preferred. |
| **Role suggestion** | ✅ | After quiz | Offline heuristic or Ollama if configured. |
| **Task assignment** | ✅ | Result / lanyard card | Top tasks from **fixed catalogue** (never free-text invent). |
| **Team roster** | ✅ | Board **Team roster** | Per-role cards + people list; `RosterExport` JSON shape for future HTML. |
| **Asset browser** | ✅ | Board **Hub resources** | Essentials (water) first; collapsible places; search; restricted gated. |

**Code:** `DoorFlowView.swift`, `DoorFlowService.swift`, `CompositeInferenceClient.suggestRole` / `selectTasks`.

---

## 6. Ask (playbook agent)

| Function | Status | Where | How it works |
|---|---|---|---|
| **Ask the playbook** | ✅ | Board **Ask** panel | Question → intent → structured facts + gated plan/guide passages → grounded answer → optional model rewrite. |
| **Hub-scoped plan** | ✅ | Automatic | Only *this* hub’s CRP chunks + regional guide. |
| **Setup / role answers** | ✅ | e.g. “How do we set up?”, “Hub Supervisor responsibilities?” | Catalogue steps + hub address / water / neighbours. Must not punt to PDF. |
| **Assets answers** | ✅ | e.g. “What assets are available?” | Structured public asset list in context pack. |
| **Privacy on retrieval** | ✅ | Public view | Plan prose redacted if it names restricted facilities (asset table alone is not enough). |
| **Markdown render** | ✅ | Answer card | Bold + line spacing / numbered lists via `MarkdownText`. |
| **Summarised label honesty** | ✅ | Mode line on answer | “Summarised by local model” only if remote model actually answered; else grounded / not summarised. |

**Code:** `AskPanel` → `AppModel.ask` → `AskService` → `HubFactStore` / `ModelContextPack` / `CompositeInferenceClient`.

**Example chips in UI:** open hub, setup, water tank, roles, neighbours, plan currency.

---

## 7. Local AI (Ollama / LM Studio)

| Function | Status | Where | How it works |
|---|---|---|---|
| **Endpoint config** | ✅ | Settings → Local model | Base URL (default Ollama `http://127.0.0.1:11434/v1` or LM Studio `:1234/v1`), model name, optional API key. |
| **Test connection** | ✅ | Settings | `GET /models`; may auto-pick model if name is placeholder. |
| **Chat completions** | ✅ | Used by Ask / summarise / door flow | Retries without JSON mode if Ollama 400s. |
| **Offline fallback** | ✅ | Always | Board and Ask work with model off; posture never needs model. |

**Code:** `NodeConfig`, `OpenAICompatibleClient`, `CompositeInferenceClient`, `OfflineInferenceClient`.

---

## 8. Regional map

| Function | Status | Where | How it works |
|---|---|---|---|
| **Regional MapKit** | ✅ | Sidebar **Regional map** | Full detail map: pins for 125 hubs (lat/lon from corpus). |
| **Pin colour posture** | ✅ | Default | green / watch / act / respond. |
| **Pin colour plan age** | ✅ | Toggle **Plan age** | Current / ageing / stale / missing (SDG slide). |
| **Home pin** | ✅ | House icon | Your configured hub. |
| **List with address** | ✅ | Below map | Name, address, TA, posture, coordinates. |
| **Open hub from pin/row** | ✅ | Tap | Switches to that hub’s board (does not change home unless you choose Make this home). |

**Code:** `MapBoardView.swift`, `AppModel.openRegionalMap` / `showRegionalMap`.

---

## 9. Not built / out of scope for this build

| Function | Status | Notes |
|---|---|---|
| Live Metlink / GeoNet / MetService adapters | 🔲 / teammate | Protocol ready: `FeedAdapter` + `TEAMMATE_FEEDS.md` |
| Print / A4 board | 🔲 | Folder `Views/Print` empty |
| EOC roll-up / multi-node sync | 🔲 | Architecture v2 |
| Auth / accounts | 🔲 | By design for hub kit code only |
| Chat history persistence | 🔲 | Ask is per-session in UI |

---

## 10. Suggested test order (your walkthrough)

1. **First launch**. set home hub (e.g. Avalon or Newtown). 
2. **Board**. posture banner, assets, neighbours. 
3. **Ask**. supervisor responsibilities; setup; assets available. 
4. **Settings**. Ollama test connection; Ask again; toggle model off and confirm “not summarised”. 
5. **Walk-in**. fill a few people / priority roles. 
6. **Replay**. +1h / +4h; posture tiles change. 
7. **Feeds → Kill** one source. Degradation copy. 
8. **Regional map**. pins, plan age toggle, open neighbour, **Back to your hub**. 
9. **Coordinator unlock** `HUBKIT`. restricted rows appear. 

Note pass/fail + anything wrong in the answer card (label, privacy, markdown, map).

---

## 11. Architecture invariants (for judging Q&A)

1. **Posture is rules-only**. model cannot raise severity. 
2. **Tasks are catalogue-only**. model selects IDs / reorders; does not invent instructions. 
3. **Privacy on retrieval**. restricted names filtered from plan prose in public view. 
4. **Age on every fact**. stale feeds must say so. 
5. **Local-first**. works without Ollama; degrades when quiet, not when it matters.

---

*Handoff snapshot for testing. Corpus © WREMO / GWRC. Attribute; do not relicense.*
