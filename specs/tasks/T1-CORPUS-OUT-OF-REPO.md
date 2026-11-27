---
id: T1-CORPUS-OUT-OF-REPO
title: Remove every corpus-derived file from HEAD, send corpus builds to a gitignored dir, and guard it
status: merged
branch: T1-CORPUS-OUT-OF-REPO
worktree: C:\wt\CHORD\T1-CORPUS-OUT-OF-REPO
allow_paths:
  - .gitignore
  - ingest_wremo.py
  - tools/build_plan_chunks.py
  - tools/check_published.py
  - tools/test_check_published.py
  - tools/corpus-inventory.txt
  - out/
  - HubNode/HubNode/Resources/Corpus/
dod_command: python -m unittest tools.test_check_published -v && python tools/check_published.py
dod_exit: 0
review_gate: codex {verdict:pass}
requirements:
  - R1. The repository shall contain at HEAD no path listed in tools/corpus-inventory.txt and no row whose sensitivity column is restricted.
  - R2. WHEN ingest_wremo.py or tools/build_plan_chunks.py runs without an explicit output flag, the tool shall write under corpus/, which .gitignore excludes.
acceptance:
  - 1. tools/corpus-inventory.txt lists every tracked corpus-derived path found by the sweep (all of out/ and HubNode/HubNode/Resources/Corpus/), and none of them is tracked after the change; test_inventory_paths_untracked asserts it against `git ls-files`. [R1] [dod arm 1]
  - 2. check_published.py exits 1 naming the file when a tracked file matches an inventory path, a CSV row has sensitivity=restricted, or a file carries the WREMO guide marker strings; test_detects_inventory_path, test_detects_restricted_row and test_detects_guide_marker build each case in a temp git repo. [R1] [dod arm 1]
  - 3. check_published.py exits 0 at HEAD of this branch. [R1] [dod arm 2]
  - 4. The default output directory of both tools is corpus/ and .gitignore contains `corpus/`; test_default_out_dir reads each tool's argparse default. [R2] [dod arm 1]
depends_on: []
parallelizable_with: [T1-NODE-SCAFFOLD, T1-DESIGN-RECONCILE]
# DESIGN-RECONCILE starts after SCAFFOLD; it may still overlap this card.
plan_ref: plans/design-review-hardening.md#7
budget: 220
sweep: "git ls-files | rg '^(out/|HubNode/HubNode/Resources/Corpus/)' found 133 paths: out/ (PDF, 114 CRP txt, assets.csv, corpus.json, guide_chunks.jsonl, hubs.csv) and Resources/Corpus (assets, guide_chunks, hubs csv/json, neighbours, plan_chunks, roles, staleness, task_templates)"
forbid: [git history rewrite, force push, any push to upstream joshuatj/ai-hackathon-2026]
non_goals:
  - Purging git history or forks; HEAD of Asun28/CHORD only.
  - Proving copyrighted text is absent beyond the inventory and marker check; a human reviews the inventory.
  - Keeping the HubNode build working; the legacy build and runtime are unsupported after removal.
  - Fictional demo data (T1-NODE-SCAFFOLD).
---

# T1-CORPUS-OUT-OF-REPO

## Deliverable
Corpus-derived files leave HEAD. The corpus tools write to a gitignored
`corpus/`. A stdlib Python guard with tests stops them coming back.

## Acceptance (DoD = command + exit code + assertion; paired with the closed `acceptance:` list)
```powershell
python -m unittest tools.test_check_published -v && python tools/check_published.py
```
- Expected exit code: 0
- Assertion: all guard tests pass and the guard finds nothing at HEAD.
