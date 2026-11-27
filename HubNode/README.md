# HubNode

> **Legacy notice (November 2026).** HubNode is frozen. It stays in the repository as a legacy demo and receives no changes. ADR-010 in `architecture.md` replaces it with the web node in `node/`.
>
> - **Build and runtime are unsupported.** The corpus it loads (`Resources/Corpus/`) was removed from the repository by T1-CORPUS-OUT-OF-REPO, so a fresh checkout has no hubs, assets, roles or tasks to load. Nobody on the team can build or test Swift.
> - **Known issues, not fixed here:**
>   1. Coordinator unlock is global over HTTP: one unlock on the Mac (`coordinatorUnlocked`, `App/AppModel.swift:301`) serves the coordinator view, including restricted assets, to every HTTP client. The code `HUBKIT` is a literal in this public repository (`App/AppModel.swift:50`).
>   2. Contacts override: `GET /api/v1/hub/needs-offers?contacts=1` returns contact details to any client (`Services/HTTP/HubNodeHTTPServer.swift:159`).
>   3. Raw seed routes: `GET /api/v1/seed`, `/seed.json` and `/demo-seed-data-v0.3.json` serve the seed data with no gate (`HubNodeHTTPServer.swift:174`, `:198`).
>   4. Wildcard CORS: every response sends `Access-Control-Allow-Origin: *` (`HubNodeHTTPServer.swift:488`).
>   5. Plaintext LAN: the optional LAN bind serves plain HTTP with no TLS and no authentication.
> - **Never enable LAN bind** (Settings, Web board, optional LAN). With the issues above, it publishes restricted assets and contact details to everyone on the network.
>
> Guarantee status for HubNode and the web node: [`docs/CAPABILITIES.md`](../docs/CAPABILITIES.md).

Local-first Community Emergency Hub board for the Wellington region.

Native **macOS** app (SwiftUI + MapKit + SwiftData) that turns WREMO’s 114 published Community Response Plans (125 hubs) into a live ops board: national feeds → CAP → deterministic posture rules → guide-sourced tasks + corpus-grounded Ask.

Companion docs in the repo root: `architecture.md`, `scope-and-pitch-v4.md`.

**Design standards:** [`DESIGN.md`](DESIGN.md) (copy and UI). No em dashes in app strings. Local check: `scripts/check-no-emdash.sh` (gitignored; see DESIGN.md).

**Feature inventory / test sheet:** [`FEATURES.md`](FEATURES.md).

## Open in Xcode

```bash
open HubNode/HubNode.xcodeproj
```

Build & run the **HubNode** scheme (My Mac).

## What works today

| Capability | Status |
|---|---|
| **Set home hub** (this Mac lives in one hall) | ✅ First-run + Change hub |
| Home-first board: walk-in, roles, tasks, situation | ✅ |
| **Ask the playbook** (guide + this hub’s CRP + facts) | ✅ |
| **LM Studio / Ollama** OpenAI-compatible endpoint | ✅ Settings |
| Regional map browse (optional) | ✅ |
| Plan-staleness colour mode (SDG 13.1.3) | ✅ |
| Replay fixture timeline | ✅ |
| Age badges + kill-a-feed | ✅ |
| Coordinator unlock (`HUBKIT`) | ✅ |
| Board works with model offline | ✅ |
| `FeedAdapter` for teammate APIs | ✅ |
| **Web board over HTTP** (Companion) | ✅ Settings → Open board |

## Web board (many devices)

HubNode embeds a local HTTP server (default `http://127.0.0.1:8787`):

| Path | What |
|---|---|
| `/` | Live board tabs: My shift, Situation, Needs & offers, Roster, Monitor, Public info, Ask Kea |
| `/console` | Bundled Hub Companion demo console |
| `/api/v1/hub/*` | JSON projection (status, situation, roster, tasks, my-shift, monitor, needs-offers, public-info, runbooks, kea) |
| `POST /api/v1/hub/ask` | **Kea** - same `AskService` path as Mac Ask |

**Model / agent config is SwiftUI only:** **Settings → Kea / Ask agent (local model)**. Web clients use that endpoint; they cannot pick another agent.

**HubNode → Settings… → Web board:** enable, port, optional LAN, **Open board in browser**.

SwiftUI board is unchanged. Web is the multi-person hall surface.

## Home hub (community hall mode)

On **first launch**, choose which Community Emergency Hub this device belongs to. That is persisted.

The app then defaults to **that hub’s operations board**. not a free-floating map of the region:

- Situation for *this* place 
- Walk-in / role assignment 
- Ask (regional guide + **this hub’s** plan prose) 
- Neighbours, assets, tasks 

**Home** and **Change hub** are in the toolbar. Browsing another hub is optional via **Regional map**.

## Local AI (LM Studio / Ollama)

**HubNode → Settings** (or macOS Settings menu):

| Field | LM Studio | Ollama |
|---|---|---|
| Base URL | `http://127.0.0.1:1234/v1` | `http://127.0.0.1:11434/v1` |
| Model name | as shown in LM Studio | e.g. `llama3.2` |
| API key | usually empty | usually empty |

1. Start LM Studio or `ollama serve` with a model loaded. 
2. Enable **Use local inference**. 
3. **Test connection**. 

**What the model is allowed to do:** situation prose, task *ordering* from the fixed catalogue, role fit, rewriting Ask answers from retrieved passages.

**What it never does:** decide posture, invent task text, bypass the privacy gate. Retrieval and structured lookups run in code first; the model only sees gated context. If the server is down, Ask still returns deterministic grounded passages.

## Demo path

1. Launch → **pick your hub** (e.g. Newtown). 
2. Board opens on **Your hub** with posture + Ask. 
3. Try Ask: *“What are the priority roles?”* / *“Where is the water tank?”* 
4. **Walk-in** a few people. Priority roles fill first. 
5. Scrub **Replay**. posture rises; Summarise uses local model if connected. 
6. **Regional map** if you need the SDG plan-age slide. 
7. Unlock coordinator with `HUBKIT` for restricted assets.

## Team split

- **Core (this app):** home hub, store, CAP, rules, board, Ask, door flow, fixtures, local inference client. 
- **Teammates:** `FeedAdapter` for GeoNet, Metlink, GWRC, MetService, HTML.

Contract: `HubNode/Feeds/FeedAdapter.swift`, `TEAMMATE_FEEDS.md`.

## Corpus

Bundled under `HubNode/Resources/Corpus/` (from `out/` + plan chunks).

- **Not open for redistribution.** GWRC CC BY-NC-ND; WREMO © all rights reserved. 
- Attribution always on-screen.

## Tests

```bash
xcodebuild -scheme HubNode -destination 'platform=macOS' test
```
