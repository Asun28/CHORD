# Lessons

Durable rules this repository learned from its own review blocks and
incidents. Append-only: one dated line per lesson, written at CLOSE of the
card that learned it, only when a review block or an incident taught a
rule the playbook did not already state. Past lines are never rewritten;
a superseded lesson gets a new line that names it. PREPARE reads this
file once per card.

Format: `- YYYY-MM-DD <card or incident>: NEVER|ALWAYS|NOTE <rule> (source: <verdict, PR or incident ref>)`

## Lessons
- (none yet)
- 2026-11-26 T1-NODE-SCAFFOLD: ALWAYS render the page module's default export in a page test, not the component it calls: board.test.ts called HomeBoard directly and still passed with an empty page (source: T1-NODE-SCAFFOLD R3 decision 1, F1)
- 2026-11-27 T1-CORPUS-OUT-OF-REPO: ALWAYS write dod_command as an && chain that cmd.exe and PowerShell 7 both parse: the loop reruns the DoD under the platform shell, where 'a; if ($LASTEXITCODE -eq 0) { b }' exits 2 (source: T1-CORPUS-OUT-OF-REPO attempt 1 loopDod, owner amendment rev 1)
- 2026-11-27 T1-NODE-RULES-REPLAY: ALWAYS state in a store card that a message's supersession is the earliest Update or Cancel referencing it, and that ingest and its effects commit as one batch: R3 blocked the first candidate for last-writer-wins supersession and a non-atomic ingest (source: T1-NODE-RULES-REPLAY R3 decision 1, F1-F3)
- 2026-11-27 T1-DESIGN-RECONCILE: ALWAYS sweep every allow_paths file of a docs card for real restricted names before it edits them: R3 blocked lines whose names predated the card, because an edited line keeps what it holds (source: T1-DESIGN-RECONCILE R3 decision 1, F1-F4)
