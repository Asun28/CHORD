---
id: T1-NODE-SCAFFOLD
title: Web node scaffold in node/ on Next.js 16 + vinext + wrangler + D1, with a runtime spike receipt
status: todo
branch: T1-NODE-SCAFFOLD
worktree: C:\wt\CHORD\T1-NODE-SCAFFOLD
allow_paths:
  - node/
dod_command: npm --prefix node ci && npm --prefix node run check && npm --prefix node run build
dod_exit: 0
review_gate: codex {verdict:pass}
requirements:
  - R1. The node shall build on Windows with pinned versions of next, vinext, vite and wrangler.
  - R2. The node shall load the fictional demo corpus into local D1 and render the home hub board from it, labelled fictional.
  - R3. The node shall export a scheduled handler that a local one-off scheduled invocation can call.
acceptance:
  - 1. node/package.json pins exact versions (no ^ or ~) and defines scripts dev, build, check (tsc --noEmit, eslint, node --test src/lib), db:migrate and db:seed; spike.test.ts asserts the pins and script names. [R1] [dod arm 1]
  - 2. node/migrations/0001_init.sql creates the plan section 5 tables; corpus-load.test.ts runs it and the seed against an in-memory SQLite (node:sqlite) and asserts hub, asset, role and task_template counts equal the fixture's. [R2] [dod arm 1]
  - 3. node/fixtures/demo-corpus.json holds only invented places and people, at least one restricted asset, the 8 role codes and task templates each with a source_ref, and a top-level "fictional": true; fixture.test.ts asserts the shape and the flag. [R2] [dod arm 1]
  - 4. GET / renders the home hub name and a visible "Fictional demo data" label; board.test.ts renders the page module with the seeded fixture and asserts both strings. [R2] [dod arm 1]
  - 5. node/SPIKE.md records the vinext result on Windows for build, D1 binding read, Set-Cookie with HttpOnly and a scheduled invocation via `wrangler dev --test-scheduled`, and names vinext or OpenNext as the runtime decision. (reviewer-verified against the diff) [R1][R3] [dod arm 2]
  - 6. `npm --prefix node run build` exits 0. [R1] [dod arm 3]
depends_on: []
parallelizable_with: [T1-CORPUS-OUT-OF-REPO]
plan_ref: plans/design-review-hardening.md#7
budget: 250
non_goals:
  - Rules, store semantics, session gate, print view (later cards).
  - Cloudflare deploy or any remote D1; local only.
  - Automatic local cron; scheduled handler is invoked manually.
---

# T1-NODE-SCAFFOLD

## Deliverable
`node/` holds the CHRD Next.js 16 scaffold (AGENTS.md and CLAUDE.md
rules carried over), made Workers-ready with vinext and wrangler. It has a
D1 schema, a fictional seed and a minimal board. The spike receipt
decides between vinext and OpenNext before any feature card starts.

## Acceptance (DoD = command + exit code + assertion; paired with the closed `acceptance:` list)
```powershell
npm --prefix node ci && npm --prefix node run check && npm --prefix node run build
```
- Expected exit code: 0
- Assertion: install, typecheck, lint, tests and build all pass on Windows.
