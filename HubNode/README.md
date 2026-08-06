# HubNode

Local-first Community Emergency Hub board for the Wellington region.

Native **macOS** app (SwiftUI + MapKit + SwiftData) that turns WREMO’s 125 Community Response Plans into a live ops board: national feeds → CAP → deterministic posture rules → guide-sourced tasks + corpus-grounded Ask.

Companion docs in the repo root: `architecture.md`, `scope-and-pitch-v4.md`.

**Design standards:** [`DESIGN.md`](DESIGN.md) (copy and UI). No em dashes in app strings. Run `scripts/check-no-emdash.sh` before push.

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
