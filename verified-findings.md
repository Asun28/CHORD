# Verified Findings: Wellington Hub Corpus
**Ingest completed 6 August 2026. Every number below is computed from source data, not estimated.**

Sources: hub locations from GWRC's public ArcGIS layer; response plans and Hub Guide from WREMO.
Attribution required on screen: **GWRC (CC BY-NC-ND 4.0)** and **WREMO (© all rights reserved)**. Redistribution is not granted by either licence: permission requested 6 Aug.

---

## 1. The SDG indicator

Official indicator **13.1.3 / 11.b.2**: *proportion of local governments that adopt and implement local disaster risk reduction strategies.* Community Response Plans are those strategies. Nobody currently reports this figure for the Wellington region.

| Measure | Value |
|---|---|
| Community Emergency Hubs in the region | **125** |
| Hubs with a published response plan | **114 (91%)** |
| Hubs with a plan reviewed in the last 24 months | **93 (74%)** |
| Ageing (24 to 48 months) | 19 |
| Stale (>48 months) | 2 |
| Hubs with no published plan | 11 |

**Oldest plan still in force: Paraparaumu North: March 2019, 7 years 5 months.** (That hub is also listed as closed for renovations.) Then Riverstone Terraces (2021), Manor Park (2022).

**Method note to state out loud:** the 24-month currency threshold is ours: WREMO publishes no review cycle. The 91% figure requires no assumption at all. Report both; the gap between them is the point.

---

## 2. The second finding: one agency, two registers, no shared identifier

The region's hub register and its own plan library disagree on what the hubs are called.

| | Hubs registered | Plans matched |
|---|---|---|
| Wainuiomata | 7 | 2 (Homedale, Parkway) |
| Masterton | 5 | 4 |

Unused plan files name places the register doesn't list. Nine plan links could not be matched to any registered hub. One plan (`Reikorangi`) matched only fuzzily against the register's `Reikiorangi`: a spelling difference between two datasets from the same organisation. Days Bay's link points at Eastbourne's PDF.

This is the fragmentation thesis demonstrated *inside a single agency*, which is stronger and more specific than any argument about file formats.

---

## 3. Corpus extracted

| | |
|---|---|
| Plans with text extracted | **114 / 114** |
| Neighbouring-hub relationships parsed | **114 / 114**: 347 edges, median 3 per hub |
| Kit contents parsed | **114 / 114** |
| Named assets identified | **4,130**: ~33 per hub |
| Hub geometry | from GWRC ArcGIS layer, WGS84 |

The 347 neighbour edges are the peer topology for the one-node-per-hub architecture. WREMO wrote the failover graph without meaning to.

---

## 4. The privacy gate, and what it caught

**3,190 assets public · 940 withheld · 0 sensitive terms remaining in the public set.**

| Withheld category | Count |
|---|---|
| medical / health | 459 |
| early childhood | 288 |
| aged care / retirement | 100 |
| housing / flats | 42 |
| custodial / protective | 16 |
| other | 35 |

**This was not theoretical.** Three rounds of review caught real material heading for an unauthenticated screen. The real names stay out of this public document; the examples below are fictional and keep the shape of each name that slipped through:

- A council-housing block listed with a "Park" street name and the label "(council housing)": classified public because "council housing" matched no housing pattern while "Park" matched a public one. Fictional example: `Example Court Flats, Example Park Rd, Exampleville (council housing)`.
- Two medical practices whose names end in "Medical Care" and "Medical": slipped past a pattern that only matched "medical cent(re)". Fictional examples: `Example Park Medical Care`, `Exampleville Medical`.
- A kōhanga reo: an early-childhood centre. Fictional example: `Te Kōhanga Reo o Example`.
- An aged-care facility whose name ends in "at the Park": one of a suburb's aged-care facilities, caught by "park" before anything else. Fictional example: `Example Village at the Park`.

And one inconsistency worth naming: kindergartens were public while playcentres were withheld. Same population: under-fives who cannot self-evacuate. All early-childhood settings are now withheld; primary and secondary schools stay public because they are hub venues and publicly known.

> *"We found council housing, four categories of medical facility, and an early-childhood centre heading for a public screen. We found them on day one, and we gated them. That's what the missing expertise actually looks like, not knowing the data exists, but knowing what not to do with it."*

---

## 5. Still open

1. **`task_templates.csv`** (state checked 27 November 2026): no copy is tracked in the repository. T1-CORPUS-OUT-OF-REPO removed both copies (`tools/corpus-inventory.txt` lines 11 and 135). The hand-reviewed HubNode copy had 101 rows, all `needs_review=no`; the `out/` copy had 95 rows, all `needs_review=yes`. A fresh run of `ingest_wremo.py` (lines 727 to 741) writes `corpus/task_templates.csv` (gitignored) with an empty `role_code` and `needs_review=yes` on every row, so the review has to be redone on each rebuild before "every task traces to a page in WREMO's guide" holds for the real corpus. The web node runs on the 5 fictional templates in `node/fixtures/demo-corpus.json`, each with a role code and a `source_ref` (`node/src/lib/fixture.test.ts`).
2. **`assets.csv`**: automated checks are clean in both directions; a human skim of the 940 withheld rows is the remaining assurance.
3. **11 hubs with no published plan**: five are named so far (Te Marua, Wallaceville, Days Bay, Stokes Valley (Tawhai), Featherston). Verify by hand before quoting any of them individually.

## 6. Operational note

Keep `--out` outside the Nextcloud tree. Mid-session, sync relocated all 114 source PDFs, which broke a run until the script learned to fall back to its cached extracted text. That fallback is now permanent, and it is the same last-known-good behaviour the architecture requires at the feed layer.

---

*All figures verified against source data 6 August 2026.*
