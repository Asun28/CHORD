# Product page

Source for <https://joshuatj.github.io/ai-hackathon-2026/>.

`index.html` is a single self-contained file. No build step, no dependencies, no
framework. Edit it and push to `main`. `.github/workflows/pages.yml` publishes
this folder and nothing else.

To preview locally, open the file directly or serve the folder:

```bash
python3 -m http.server -d docs 8000   # http://localhost:8000
```

## Where the numbers come from

Every figure on the page traces to a document in this repo. Update the page when
these change.

| On the page | Source |
|---|---|
| 125 hubs, 114 plans (91%), 93 current (74%) | `verified-findings.md` §1 |
| 347 neighbour edges, 4,130 assets, 940 withheld | `verified-findings.md` §3, §4 |
| Zero declaration / tsunami / fire danger feeds | `scope-and-pitch-v4.md` §5 |
| Posture rules, CAP normalisation, the poll loop | `architecture.md` |
| Roles, walk-in flow, Ask Kea, privacy gate, local inference | `HubNode/FEATURES.md` |
| Web board over local HTTP, tabs, `/api/v1` projection | `HubNode/FEATURES.md` §9, `HubNode/README.md` |
| What is built vs fixture-backed vs not shipped | `HubNode/FEATURES.md` §3, §9, §10 |
| SDG targets 11.b, 13.1, 16.10, 1.5 | `Pitch Deck/pitch_script_draft.md`, `sdg-alignment.md` |

## House rules this page follows

- **No em dashes or en dashes**, per `HubNode/DESIGN.md`. Full stops, commas or
  ASCII hyphens instead.
- **Attribution on screen.** GWRC (CC BY-NC-ND 4.0) and WREMO (© all rights
  reserved) appear in the hero board footer and the page footer.
- **No corpus.** Neither licence grants redistribution, so no plan text, asset
  rows or hub coordinates are published here. The hero board is an illustration
  with invented values.
- **Honest status.** The "what is real today" section states plainly that replay
  is fixture-backed and live adapters are not shipped. Keep it accurate as the
  build lands.
- **The fictional demo console is not hosted here.** `Wellington Design System
  Draft/export/Hub Companion Demo (offline).html` (bundled in the app as
  `Resources/WebUI/companion-console.html`, served at `/console`) runs on a
  fictional M7.1 scenario whose seed data says: *"Do not present outside a
  clearly-labelled demo context."* The page links to it in the repo instead, so
  the demo-pack README and that notice arrive with it. Do not copy it into
  `docs/`.

## Two web surfaces, do not confuse them

| | Offline console | Live board |
|---|---|---|
| Served at | `/console` | `/` (port 8787) |
| Source | `Resources/WebUI/companion-console.html` | `Resources/WebUI/index.html` |
| Data | Frozen fictional seed JSON | Live `/api/v1/*`, polled every 5s |
| Screens | 11, five languages, simulate-offline | My shift, Situation, Needs & offers, Roster, Monitor, Public info, Ask Kea |

The page's "One Mac in the hall" card describes the **live board only**. Do not
attribute the console's extra screens (Am I impacted?, Records, Status report,
the five languages) to it, since those are not in the live board today.
