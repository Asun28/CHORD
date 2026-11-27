---
id: T1-NODE-VIEW-GATE
title: Per-session coordinator gate with view-mode filtering, proved by two-cookie-jar tests
status: todo
branch: T1-NODE-VIEW-GATE
worktree: C:\wt\CHORD\T1-NODE-VIEW-GATE
allow_paths:
  - node/src/server/session.ts
  - node/src/server/session.test.ts
  - node/src/lib/view-model.ts
  - node/src/lib/view-model.test.ts
  - node/src/app/api/unlock/
  - node/src/app/api/lock/
  - node/src/app/api/feeds/
  - node/src/app/api/fixtures/
  - node/src/app/page.tsx
  - node/src/app/hub/
  - node/tests/gate.integration.test.ts
  - node/.env.example
  - node/package.json
  - node/src/lib/fixtures-step.test.ts
  - node/migrations/0002_unlock_client.sql
  - node/src/proxy.ts
  - node/src/middleware.ts
dod_command: npm --prefix node run check && npm --prefix node run test:integration
dod_exit: 0
review_gate: codex {verdict:pass}
requirements:
  - R1. IF a request has no valid coordinator session, THEN no response shall contain a restricted asset.
  - R2. WHEN the correct code is posted to /api/unlock, the node shall set a session cookie for that browser only, valid 30 minutes.
  - R3. The node shall refuse unlock after 5 failed attempts in 15 minutes from one client, where a client is its CF-Connecting-IP only when env TRUST_CF_CONNECTING_IP is set (the Cloudflare edge overwrites that header) and all requests count as one client otherwise; it shall also refuse unlock after 50 failed attempts in 15 minutes across all clients.
  - R4. IF a state-changing request has an Origin other than the node's own, THEN the node shall answer 403.
  - R5. The node shall expose no Ask, contacts or raw seed route.
acceptance:
  - 1. gate.integration.test.ts with jars A and B: A unlocks; A's board shows the fixture's restricted asset name; B's board and every GET route listed in the plan do not; B stays public after A unlocks. [R1][R2] [dod arm 2]
  - 2. Cookie is HttpOnly and SameSite=Strict, Secure unless the host is localhost, signed with HMAC-SHA256 from env SESSION_SECRET; a tampered or expired cookie (clock at 30m + 1s) gives public view; POST /api/lock ends the session. session.test.ts. [R2] [dod arm 1]
  - 3. Sixth wrong code within 15 minutes returns 429, and a right code then also returns 429 until the window passes; session.test.ts with a fixed clock. [R3] [dod arm 1]
  - 4. POST to unlock, lock, feeds pause/resume and fixtures/step with a foreign Origin returns 403; pause, resume and step without a session return 401. [R4] [dod arm 2]
  - 5. Every response that varies by view sends Cache-Control: private, no-store; no response sends Access-Control-Allow-Origin. [R1] [dod arm 2]
  - 6. GET /api/ask, /api/v1/hub/ask, any path the Worker serves with contacts=1, and /seed return 404; hashed build files under /_next/static/ are served from the asset store, hold no data, and are excluded. [R5] [dod arm 2]
  - 7. The unlock code comes from env HUB_COORDINATOR_CODE; no code literal is in node/src; .env.example lists both names empty. view-model.test.ts greps src. [R2] [dod arm 1]
depends_on: [T1-NODE-RULES-REPLAY]
plan_ref: plans/design-review-hardening.md#7
budget: 250
sweep: "HubNode defects addressed by design, not port: AppModel.swift:50,301; HubNodeAPIService.swift:369,442; HubNodeHTTPServer.swift:125,158,174,198,488"
forbid: [accounts or user database, third-party auth packages, secrets in files]
non_goals:
  - Accounts, roles beyond public and coordinator, password reset.
  - Rate limiting other than unlock attempts.
  - TLS termination for hall LAN use; localhost or Cloudflare only this version.
---

# T1-NODE-VIEW-GATE

## Deliverable
Coordinator view is a property of one browser session, never of the
node. Restricted rows are removed in the view model before render.
Integration tests run the node and drive it with two cookie jars.
`node/package.json` is in allow_paths only to add the `test:integration`
script, which runs `tests/*.integration.test.ts`.
`node/src/lib/fixtures-step.test.ts` is in allow_paths only so the step
test unlocks first and sends the session cookie and the node's own
Origin; its cursor assertions stay as they are (owner amendment).
Owner decisions (amendments 2 and 3): the unlock limit is R3 above.
`node/migrations/0002_unlock_client.sql` adds the client key column to
`unlock_attempt`; `0001_init.sql` stays unchanged. The node trusts
`CF-Connecting-IP` only when env `TRUST_CF_CONNECTING_IP` is set, which
`.env.example` lists empty; on the hall laptop the caller can set that
header, so it is ignored there. One request proxy file
(`node/src/proxy.ts`, or `node/src/middleware.ts` if the installed Next
and vinext load only that name) returns 404 for `contacts` on any path
before routing, static and metadata files included, and sets
`Cache-Control: private, no-store` on view-dependent HTML and RSC
responses in both the dev and the built runtime.

## Acceptance (DoD = command + exit code + assertion; paired with the closed `acceptance:` list)
```powershell
npm --prefix node run check && npm --prefix node run test:integration
```
- Expected exit code: 0
- Assertion: unit and integration suites pass; the integration suite starts and stops its own node process.
