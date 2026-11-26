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
