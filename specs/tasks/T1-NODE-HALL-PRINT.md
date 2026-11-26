---
id: T1-NODE-HALL-PRINT
title: Board age and stale states, A4 print view, and a disconnected start and restart acceptance on Windows
status: todo
branch: T1-NODE-HALL-PRINT
worktree: C:\wt\CHORD\T1-NODE-HALL-PRINT
allow_paths:
  - node/src/app/hub/
  - node/src/app/page.tsx
  - node/src/app/globals.css
  - node/src/components/
  - node/src/lib/age.ts
  - node/src/lib/age.test.ts
  - node/tests/print.integration.test.ts
  - node/scripts/hall-check.ps1
  - node/README.md
dod_command: npm --prefix node run check && npm --prefix node run test:integration && pwsh node/scripts/hall-check.ps1 -Offline
dod_exit: 0
review_gate: codex {verdict:pass}
requirements:
  - R1. The board shall show for every fact its observation age at the cursor and its feed's last fetch time, and mark it stale above three times the source cadence.
  - R2. IF the store cannot be read, THEN the board shall show an error banner and no posture colour.
  - R3. GET /hub/[id]/print shall render one A4 page with posture, roles, tasks, public assets, a timestamp per fact and the render time, and no restricted asset in any session.
  - R4. WHEN started from an initialised local D1 with no network, the node shall serve board, replay step and unlock, and keep feed pause and observations across a restart.
acceptance:
  - 1. age.test.ts: age at cursor, fetch age and stale flag for cadence 300s at ages 899s and 901s; paused feed tile reads "paused" with its last fetch time. [R1] [dod arm 1]
  - 2. print.integration.test.ts: the board with an injected failing store shows the error banner and none of green, watch, act, respond. [R2] [dod arm 2]
  - 3. print.integration.test.ts: print page HTML for a coordinator session and a public session contains no restricted fixture name, contains the render time and one timestamp per listed fact, and the print stylesheet sets @page size A4. [R3] [dod arm 2]
  - 4. hall-check.ps1 -Offline: refuses to run unless DNS resolution of a public host fails; starts `wrangler dev` on local D1, checks GET / is 200, steps a fixture, unlocks with a test code, pauses a feed, stops the node by pid, restarts, and checks the pause and the stepped observation remain; exits non-zero on any failed check and leaves no process running. Receipt pasted. [R4] [dod arm 3]
  - 5. node/README.md documents hall setup (npm ci, db:migrate, db:seed while online), the manual fixture step, and that cloud-only clients lose access when the uplink fails. (reviewer-verified against the diff)
depends_on: [T1-NODE-VIEW-GATE]
plan_ref: plans/design-review-hardening.md#7
budget: 250
sweep: "board surfaces after T1-NODE-VIEW-GATE: app/page.tsx, app/hub/[id]/page.tsx (+ new print/page.tsx), globals.css (@media print), components/ (tiles, age badge); age logic in lib/age.ts; HubNode reference AgeBadge.swift and HubBoardView.swift:422; no other file renders facts"
forbid: [network access in hall-check after its offline precondition]
non_goals:
  - Browser offline cache or service worker.
  - Automatic polling or a Windows scheduler wrapper.
  - Neighbours panel, roster detail, regional map.
---

# T1-NODE-HALL-PRINT

## Deliverable
The board is honest about time and failure, prints to one A4 page, and
a script proves the node runs and keeps state on a laptop with no
network.

## Acceptance (DoD = command + exit code + assertion; paired with the closed `acceptance:` list)
```powershell
npm --prefix node run check && npm --prefix node run test:integration && pwsh node/scripts/hall-check.ps1 -Offline
```
- Expected exit code: 0
- Assertion: suites pass and hall-check reports every offline check passed after a restart.
