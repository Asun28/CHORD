---
slug: design-review-hardening
title: Review the CHORD design against its build and close the gaps that break its own guarantees
author: asun28 (owner)
status: draft
created: 2026-11-26T10:30:00Z
source: human
---

# Intent: Review the CHORD design against its build and close the gaps that break its own guarantees
Author: asun28 (owner). Status: draft.

## Problem
CHORD (AWS AI Hackathon 2026) has a strong written design: `architecture.md`
(ADR-001..009), `omega-engineering-review.md`, `verified-findings.md`, the
Hub Companion PRD v0.3 and `HubNode/FEATURES.md`. The build has drifted from
it, and some drift breaks guarantees the pitch states on stage:

1. Privacy gate is a screen gate, not a data gate. The public fork ships
   `HubNode/HubNode/Resources/Corpus/assets.csv` with all 940 restricted rows
   (aged care, early childhood, council housing, medical) and `out/assets.csv`.
2. Coordinator mode is process-global. `AppModel.swift:301` derives the Ask
   view from one `coordinatorUnlocked` flag; `POST /api/v1/hub/ask` calls
   `app.ask`, so one unlock on the Mac serves restricted answers to every
   HTTP client, including LAN clients when LAN bind is on (no TLS, no auth).
   The unlock code `HUBKIT` is a literal in a public repo.
3. Corpus licence boundary is broken. The Omega review section 8 and
   architecture section 9 say "ship ingestion instructions, not ingested
   content". The repo publishes the WREMO Hub Guide PDF, 114 CRP texts,
   `guide_chunks.jsonl` and `plan_chunks.jsonl` (WREMO all rights reserved;
   GWRC layer CC BY-NC-ND).
4. Two products, two rule sets. HubNode follows ADR-005 (tasks selected from
   the catalogue, never authored). The Hub Companion PRD has Kea "turn an
   answer into a task" with AI-drafted steps, and an outbound REST / A2A /
   MCP surface with an EOC token, while architecture section 1 says no
   aggregation and no auth in v1.
5. Promised mechanisms are missing: live feed adapters (fixtures only),
   print / A4 floor tier (`Views/Print` empty), retraction over a
   notification channel (no channel exists).
6. Docs disagree with each other: `verified-findings.md` section 5 says every
   task template is `needs_review=yes`; the CSV now has 101 rows, all `no`.
7. The owner's local `D:\Projects\CHRD` is a Next.js 16 scaffold. HubNode is
   macOS SwiftUI; the owner's machine is Windows and cannot build or test it.

## Proposed outcome
- A written design review that lists each guarantee, its evidence in code,
  and a verdict (holds / partial / broken), agreed with a second reviewer
  (Codex).
- A plan and validated cards that fix the broken guarantees first
  (privacy, licence boundary, per-request view mode), then reconcile the
  two product designs, then fill missing mechanisms.
- Every card has a DoD command that runs on this Windows machine, or it
  names the macOS step and who runs it.

## Affected users and systems
Hub volunteers and coordinators (board, Ask, door flow); the HubNode macOS
app (`HubNode/`); the Hub Companion web console (`Resources/WebUI/`,
`Wellington Design System Draft/`); the corpus build tools
(`ingest_wremo.py`, `tools/build_plan_chunks.py`); GitHub Pages (`docs/`);
the public fork `Asun28/CHORD` and upstream `joshuatj/ai-hackathon-2026`.

## Constraints
- Restricted asset names are sensitive location data about vulnerable
  people. They must not be published in the repo, Pages or any API without
  the coordinator gate.
- WREMO content is all rights reserved; GWRC hubs layer is CC BY-NC-ND 4.0.
- Removing a file from HEAD does not remove it from git history or from
  forks; history rewrite on a shared/published branch is prohibited here
  without an owner decision.
- Posture stays rules-only (ADR-003); tasks stay catalogue-only (ADR-005).
- No em or en dashes in product copy (ADR-009).
- Development target only. No deploy, no push to upstream without owner say.

## Open questions
- (none)

## Resolved
- Q1 Runtime: port the node to a web runtime built from the
  `D:\Projects\CHRD` Next.js 16 scaffold, deployed as a Cloudflare website
  (owner, 2026-11-26). HubNode (Swift) is frozen as a legacy demo.
- Q2 Where changes go: every change lands in the owner's fork
  `Asun28/CHORD`; nothing goes upstream. A history purge (force push) was
  not authorised and stays a separate owner decision.
- Q3 Tasks: ADR-005 wins. Tasks are selected from the catalogue by ID;
  the Hub Companion AI-drafted task feature is cut.
- Q4 macOS: nobody can build Swift. No card changes Swift code; every DoD
  runs on Windows.
