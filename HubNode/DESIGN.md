# HubNode design standards

Standards for product copy, UI chrome, and model-facing prompts. Follow these in Swift sources, Settings, Ask answers we author, fixture headlines, and bundled corpus `source_ref` strings we control.

---

## 1. Typography: no em dashes

**Do not use Unicode em dashes (U+2014) or en dashes (U+2013) in the app.**

| Instead of | Use |
|---|---|
| Clause break with an em dash | A full stop and a new sentence, or a comma |
| Range (for example 24 to 48 months) | ASCII hyphen: `24-48` |
| Source line (Guide then section) | ASCII hyphen with spaces: `Guide - Section` |
| Missing value placeholder | ASCII hyphen: `-` or the word `none` |

### Why

Em dashes read poorly on crowded ops boards, break markdown rendering, and look inconsistent next to model output. Hall laptops and printed boards need plain, scannable English.

### Examples

**Avoid** (em dash between phrases)

```
River: rising <em-dash> 14 min ago
Not summarised <em-dash> no model available
WREMO Hub Guide <em-dash> Accessing the hub
```

**Prefer**

```
River: rising. 14 min ago.
Not summarised. No model available. Retrieved passages shown verbatim.
WREMO Hub Guide - Accessing the hub
```

### Scope

Applies to:

- User-visible SwiftUI strings  
- Status bar and toolbar help  
- Ask grounded briefs and system prompts we write  
- Fixture headlines and offline inference copy  
- Comments and docs under `HubNode/` (keep them plain too)  
- Bundled CSV/JSONL fields we generate (`source_ref`, role text, and similar)

Does not require rewriting third-party PDF bodies we never display raw. Prefer cleaned extracts in `plan_chunks` and templates.

### Check before commit

From the `HubNode/` directory:

```bash
./scripts/check-no-emdash.sh
```

Fails the commit if U+2013 or U+2014 appear in Swift, project markdown, or bundled corpus text under `HubNode/`.

---

## 2. Related writing rules (same spirit)

1. **Full sentences** on the board and in Ask. Prefer "No model is available." over fragments stuck together with dashes.  
2. **Plain language** for volunteers under stress. Avoid clever punctuation.  
3. **Attribution** stays visible (GWRC / WREMO).  
4. **Honesty labels** stay accurate: only say the model summarised when it did.

---

## 3. Where this lives

| Doc | Role |
|---|---|
| **This file** | Design standard of record for HubNode UI and copy |
| `FEATURES.md` | What is built and how to test |
| `architecture.md` (repo root) ADR-009 | Architecture decision that points here |

New UI or Ask strings: run the check above before pushing.
