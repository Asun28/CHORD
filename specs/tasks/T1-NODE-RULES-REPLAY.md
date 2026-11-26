---
id: T1-NODE-RULES-REPLAY
title: Contracts, CAP normaliser, temporal D1 store and posture rules with the design review fixes
status: todo
branch: T1-NODE-RULES-REPLAY
worktree: C:\wt\CHORD\T1-NODE-RULES-REPLAY
allow_paths:
  - node/src/lib/
  - node/src/server/store.ts
  - node/src/server/store.test.ts
  - node/src/app/api/fixtures/
  - node/migrations/
  - node/fixtures/feeds/
dod_command: npm --prefix node run check
dod_exit: 0
review_gate: codex {verdict:pass}
freeze: true
requirements:
  - R1. The posture engine shall use rules only; a P2 observation shall raise posture only with a second source for the same hazard type and overlapping area within 60 minutes.
  - R2. IF an observation has no area geometry, THEN the matcher shall not match it to any hub.
  - R3. The store shall key a message by (source, CAP identifier) and ignore a re-fetch of a known key.
  - R4. WHEN a Cancel or Update references an earlier message, the store shall supersede it from the referencing message's sent time, including when the reference arrives first.
  - R5. WHILE a feed is paused, the store shall keep it paused across restarts until resumed.
  - R6. IF the store read fails, THEN the posture result shall be error, never green.
acceptance:
  - 1. rules.test.ts: lone P2 stays green; two P2 sources, same hazard and overlapping area, 59 minutes apart, give watch; 61 minutes apart, or different hazard types, stay green; P3 never raises. [R1] [dod arm 1]
  - 2. rules.test.ts: an alert without geometry matches no hub. [R2] [dod arm 1]
  - 3. store.test.ts against node:sqlite with 0001_init.sql: the same message fetched twice gives one row, and a re-fetch after a Cancel does not reactivate it. [R3][R4] [dod arm 1]
  - 4. store.test.ts: after Cancel at t1, a read at t1 minus 1s shows the original and a read at t1 does not; an Update arriving before its target supersedes the target once the target is stored. [R4] [dod arm 1]
  - 5. store.test.ts: pause a feed, close and reopen the database file, the feed is still paused; resume clears it. [R5] [dod arm 1]
  - 6. rules.test.ts: a store read that throws gives posture "error". [R6] [dod arm 1]
  - 7. POST /api/fixtures/step applies the next fixture file and returns the new cursor; the coordinator check is added by T1-NODE-VIEW-GATE. fixtures-step.test.ts asserts the cursor moves. [dod arm 1]
depends_on: [T1-NODE-SCAFFOLD]
plan_ref: plans/design-review-hardening.md#7
budget: 250
sweep: "Swift sources ported: CAP/CAPNormaliser.swift, Rules/PostureEngine.swift, Rules/SpatialMatch.swift, Services/ObservationStore.swift; review defects at PostureEngine.swift:136, SpatialMatch.swift:37, DomainModels.swift:254, ObservationStore.swift:46 each have a test above"
forbid: [network access in tests, model calls in posture code]
non_goals:
  - Live feed adapters; fixtures only.
  - Automatic polling; the step route and scheduled handler are invoked manually.
  - Session checks on the step route (T1-NODE-VIEW-GATE).
---

# T1-NODE-RULES-REPLAY

## Deliverable
Pure TypeScript contracts, CAP normalising and rules in `node/src/lib`,
plus a D1 store with message identity, cursor-scoped supersede and
persisted pause. The contracts and schema freeze when this card merges.

## Acceptance (DoD = command + exit code + assertion; paired with the closed `acceptance:` list)
```powershell
npm --prefix node run check
```
- Expected exit code: 0
- Assertion: typecheck, lint and all node:test suites pass, including the store tests on a real SQLite file.
