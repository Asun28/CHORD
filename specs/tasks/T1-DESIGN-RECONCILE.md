---
id: T1-DESIGN-RECONCILE
title: Make the design documents agree with the owner decisions and the build
status: merged
branch: T1-DESIGN-RECONCILE
worktree: C:\wt\CHORD\T1-DESIGN-RECONCILE
allow_paths:
  - architecture.md
  - verified-findings.md
  - scope-and-pitch-v4.md
  - Wellington Design System Draft/export/hub-companion-prd-v0.3.md
  - Wellington Design System Draft/export/what-was-built.md
  - HubNode/README.md
  - HubNode/FEATURES.md
  - docs/index.html
  - docs/CAPABILITIES.md
  - LICENSE
  - tools/check_docs.py
dod_command: python tools/check_docs.py
dod_exit: 0
tdd: false
review_gate: codex {verdict:pass}
acceptance:
  - 1. architecture.md adds ADR-010 (web node on Cloudflare Workers via the runtime T1-NODE-SCAFFOLD names, D1, hall mode under wrangler dev with local D1, local cron not automatic so hall polling is manual fixture stepping, cloud-only clients lose access when the uplink fails) and marks ADR-008 superseded. (reviewer-verified against the diff)
  - 2. ADR-005 states it binds every surface; the PRD removes AI-drafted task details and answer-to-task authoring, keeping catalogue-ID proposals with a named confirmer, and drops the bearer token, EOC token and A2A/MCP claims or marks them v2. (reviewer-verified against the diff)
  - 3. Hub counts read 125 hubs, 114 with a published plan, 11 without, everywhere they appear; verified-findings.md section 5 matches the current task_templates state. (reviewer-verified against the diff)
  - 4. docs/CAPABILITIES.md lists each guarantee from the spec review table with holds, partial or broken and its evidence, for HubNode and for the web node. (reviewer-verified against the diff)
  - 5. HubNode/README.md and FEATURES.md open with a legacy notice: frozen, build and runtime unsupported after corpus removal, known issues (global coordinator unlock over HTTP, contacts override, raw seed routes, wildcard CORS, plaintext LAN), never enable LAN bind. (reviewer-verified against the diff)
  - 6. LICENSE is MIT for the engine code, with a note that WREMO and GWRC content is not covered and is not in the repo; docs/index.html no longer claims a print fallback that does not exist. (reviewer-verified against the diff)
  - 7. tools/check_docs.py exits 0: architecture.md contains "ADR-010", no changed product-copy file contains an em or en dash, and none contains "127 hubs". [dod arm 1]
depends_on: [T1-NODE-SCAFFOLD]
parallelizable_with: [T1-CORPUS-OUT-OF-REPO, T1-NODE-RULES-REPLAY]
plan_ref: plans/design-review-hardening.md#7
budget: 300
sweep: "rg -n '127|AI-drafted|bearer|EOC|A2A|MCP|print' over the allow_paths files; each hit is resolved or kept with reason"
non_goals:
  - Licensing WREMO or GWRC content; only the engine is licensed.
  - Rewriting the pitch narrative beyond the counts and claims named here.
  - Any Swift or web code change.
---

# T1-DESIGN-RECONCILE

## Deliverable
One design: ADR-010 runtime, ADR-005 on every surface, true counts, an
engine licence, a capability matrix and an honest legacy notice for
HubNode. Runs after T1-NODE-SCAFFOLD so ADR-010 names the runtime that
`node/SPIKE.md` chose.

## Acceptance (DoD = command + exit code + assertion; paired with the closed `acceptance:` list)
```powershell
python tools/check_docs.py
```
- Expected exit code: 0
- Assertion: ADR-010 present, no em or en dash in changed product copy, no "127 hubs".
