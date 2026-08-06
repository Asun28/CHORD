# Verified Findings — Wellington Hub Corpus
**Ingest completed 6 August 2026. Every number below is computed from source data, not estimated.**

Sources: hub locations from GWRC's public ArcGIS layer; response plans and Hub Guide from WREMO.
Attribution required on screen: **GWRC (CC BY-NC-ND 4.0)** and **WREMO (© all rights reserved)**. Redistribution is not granted by either licence — permission requested 6 Aug.

---

## 1. The SDG indicator

Official indicator **13.1.3 / 11.b.2** — *proportion of local governments that adopt and implement local disaster risk reduction strategies.* Community Response Plans are those strategies. Nobody currently reports this figure for the Wellington region.

| Measure | Value |
|---|---|
| Community Emergency Hubs in the region | **125** |
| Hubs with a published response plan | **114 — 91%** |
| Hubs with a plan reviewed in the last 24 months | **93 — 74%** |
| Ageing (24–48 months) | 19 |
| Stale (>48 months) | 2 |
| Hubs with no published plan | 11 |

**Oldest plan still in force: Paraparaumu North — March 2019, 7 years 5 months.** (That hub is also listed as closed for renovations.) Then Riverstone Terraces (2021), Manor Park (2022).

**Method note to state out loud:** the 24-month currency threshold is ours — WREMO publishes no review cycle. The 91% figure requires no assumption at all. Report both; the gap between them is the point.

---

## 2. The second finding — one agency, two registers, no shared identifier

The region's hub register and its own plan library disagree on what the hubs are called.

| | Hubs registered | Plans matched |
|---|---|---|
| Wainuiomata | 7 | 2 (Homedale, Parkway) |
| Masterton | 5 | 4 |

Unused plan files name places the register doesn't list. Nine plan links could not be matched to any registered hub. One plan (`Reikorangi`) matched only fuzzily against the register's `Reikiorangi` — a spelling difference between two datasets from the same organisation. Days Bay's link points at Eastbourne's PDF.

This is the fragmentation thesis demonstrated *inside a single agency*, which is stronger and more specific than any argument about file formats.

---

## 3. Corpus extracted

| | |
|---|---|
| Plans with text extracted | **114 / 114** |
| Neighbouring-hub relationships parsed | **114 / 114** — 347 edges, median 3 per hub |
| Kit contents parsed | **114 / 114** |
| Named assets identified | **4,130** — ~33 per hub |
| Hub geometry | from GWRC ArcGIS layer, WGS84 |

The 347 neighbour edges are the peer topology for the one-node-per-hub architecture. WREMO wrote the failover graph without meaning to.

---

## 4. The privacy gate — and what it caught

**3,190 assets public · 940 withheld · 0 sensitive terms remaining in the public set.**

| Withheld category | Count |
|---|---|
| medical / health | 459 |
| early childhood | 288 |
| aged care / retirement | 100 |
| housing / flats | 42 |
| custodial / protective | 16 |
| other | 35 |

**This was not theoretical.** Three rounds of review caught real material heading for an unauthenticated screen:

- `Marshall Court Flats, Park Rd, Miramar (council housing)` — classified public because "council housing" matched no housing pattern while "Park" matched a public one.
- `Churton Park Medical Care`, `Miramar Medical` — slipped past a pattern that only matched "medical cent(re)".
- `Te Kōhanga Reo o Ōrongomai` — an early-childhood centre.
- `Village at the Park` — one of Newtown's three aged-care facilities, caught by "park" before anything else.

And one inconsistency worth naming: kindergartens were public while playcentres were withheld. Same population — under-fives who cannot self-evacuate. All early-childhood settings are now withheld; primary and secondary schools stay public because they are hub venues and publicly known.

> *"We found council housing, four categories of medical facility, and an early-childhood centre heading for a public screen. We found them on day one, and we gated them. That's what the missing expertise actually looks like — not knowing the data exists, but knowing what not to do with it."*

---

## 5. Still open

1. **`task_templates.csv`** — every row is `needs_review=yes`. Assign role codes, delete noise. ~20 minutes, and it's what makes "every task traces to a page in WREMO's guide" true rather than aspirational.
2. **`assets.csv`** — automated checks are clean in both directions; a human skim of the 940 withheld rows is the remaining assurance.
3. **Five hubs with no plan** — Te Marua, Wallaceville, Days Bay, Stokes Valley (Tawhai), Featherston. Verify by hand before quoting them individually.

## 6. Operational note

Keep `--out` outside the Nextcloud tree. Mid-session, sync relocated all 114 source PDFs, which broke a run until the script learned to fall back to its cached extracted text. That fallback is now permanent — and it is the same last-known-good behaviour the architecture requires at the feed layer.

---

*All figures verified against source data 6 August 2026.*
