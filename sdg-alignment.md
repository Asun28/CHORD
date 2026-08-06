# HubNode — What We're Building, and How It Aligns to the SDGs
**Tech NZ × AWS AI Hackathon · Wellington · 6 August 2026**

---

## 1. What we're building

**A live operations layer for volunteer-run Community Emergency Hubs.**

Wellington has 125 Community Emergency Hubs. Each is run, in WREMO's own words, *"by people like you in your local community without official assistance"*, with roles *"allocated by agreement between whoever turns up"*, a VHF radio, and no stored supplies. Each has an official Community Response Plan — 114 of them are published — naming its neighbouring hubs, its emergency water tank, its aged-care facilities and its community networks. They are PDFs, and the regional Hub Guide is 44 pages.

The guide tells a volunteer *what* to do. It does not do it. It says "create a roster", and you reach for paper and draw boxes.

HubNode reads the national and regional hazard feeds continuously, normalises everything to CAP (the international alerting standard), decides by **rule** whether a hazard matters to a specific hub, and uses a **model** only to explain the situation and to select and order tasks drawn from WREMO's own playbook. Volunteers arriving at a hub are matched to one of the eight official roles, priority roles first, and handed tasks that each trace back to a page in the guide.

### The five layers

| Layer | Function |
|---|---|
| **Ingest** | Per-feed adapters, polled at each source's own cadence, cached |
| **Normalise** | One CAP-aligned schema · trust tier · deduplication · geo-match to hub |
| **Memory** | 114 Community Response Plans + regional Hub Guide + role and task catalogue |
| **Reasoning** | Local-first inference: feed state × that hub's plan → posture + ranked tasks |
| **Delivery** | The hub board · door flow · one notification channel · printed board |

### Running today

Native local node (SwiftUI / MapKit / SwiftData) with all 125 hubs on a map; CAP normaliser with fixture replay across southerly, river, roads and quake; deterministic rules engine with unit tests; hub board showing posture, drivers, roles, tasks, assets and neighbours; age badges with a kill-a-feed demonstration; plan-age visualisation; public vs coordinator privacy gating; door flow from walk-in to role to tasks; a documented `FeedAdapter` contract so teammates can add live feeds without touching the core.

### Design commitments that matter for this document

- **The trigger is deterministic; only the guidance is generative.** Rules decide *that* something matters, so posture is explainable and reproducible. The model is confined to language and ordering.
- **Tasks are selected from an authoritative catalogue, never authored.** The system has no code path that produces an emergency instruction WREMO did not write.
- **Every displayed fact carries its age**, on its face. When a feed exceeds its expected cadence the tile degrades and says so.
- **The privacy gate lives in the data-access layer, not in a prompt.** Restricted rows never enter the model's context.
- **Local-first inference with cloud burst.** A cloud-default system degrades in exactly the conditions it exists for.

---

## 2. The problem, in verified numbers

Every figure below was computed from source data on 6 August 2026.

| | |
|---|---|
| Community Emergency Hubs in the region | **125** |
| Hubs with a published response plan | **114 — 91%** |
| Hubs with no published plan | **11** |
| Plans reviewed since January 2024 | **107 of 114** |
| Plans older than four years | **3** (2019, 2021, 2022) |
| Oldest plan still in force | **March 2019** — a hub also listed as closed for renovations |
| Named assets extracted from the plans | 4,130, of which **940 withheld** as vulnerable-population or care facilities |

**Two findings beyond the counts.**

*The plan library and the hub register disagree.* Wainuiomata has 7 hubs registered and 2 with matched plans; Masterton has 5 registered and 4 matched. Nine plan files name places the register does not list. One plan matched only fuzzily — `Reikorangi` against the register's `Reikiorangi`. Two authoritative datasets, one region, no shared identifier.

*The most decisive fact in an emergency is not machine-readable anywhere in New Zealand.* Whether a state of emergency has been declared, and where, has no API. The declaration process is email, a physical signature, and a human typing a banner onto a website. NEMA operates a CAP feed for Emergency Mobile Alert and describes it as publicly available; the URL is published nowhere. There is no public tsunami warning feed, no public fire danger API, and no public power outage API.

**What this is not.** The date distribution — 36 plans reviewed in 2026, 44 in 2025, 27 in 2024 — is evidence that WREMO is actively maintaining these plans. This is not a story about neglect. It is a story about **visibility**: nobody can see that the work is being done, including the people doing it, because the evidence is spread across 125 separate PDFs.

---

## 3. The alignment thesis

**Every relevant SDG indicator measures whether an instrument exists. None measures whether it functions.**

**And the same instrument-level measure carries three separate SDG targets.** Indicators **1.5.4**, **11.b.2** and **13.1.3** are word-for-word identical — *"proportion of local governments that adopt and implement local disaster risk reduction strategies in line with national disaster risk reduction strategies"* — and all three report against **Sendai Framework Target E**. Their national-level partners (1.5.3, 11.b.1, 13.1.2) are likewise the same measure.

So this is not a quirk of one indicator. Across Goals 1, 11 and 13, disaster resilience is assessed by a single question — *does the local government have a strategy aligned to the national one?* — and none of those three targets looks below that level.

The UN metadata defines it as *"the percentage of local governments that adopt and implement local disaster risk reduction strategies in line with national strategies."* Countries define "local government" themselves. The metadata describes adoption and alignment with national frameworks; it does not specify any assessment of the currency, quality or effectiveness of the strategy.

In New Zealand, the relevant sub-national bodies are the **16 regional CDEM Groups**, and the CDEM Act 2002 *requires* each to prepare and approve a Group Plan. So the indicator is likely at or near 100% nationally — Wellington included — by construction rather than by achievement.

That the indicator cannot see currency is not a hypothesis. The Auditor-General records that Auckland's CDEM Group Plan *"was intended to cover just 2016 to 2021"* and *"remains in place until a new plan is finalised."* A plan five years past its intended coverage still satisfies the indicator.

Meanwhile, one layer below the level the indicator counts:

- 11 hubs have no published response plan
- one plan dates from 2019
- the region's own two registers cannot agree on what the hubs are called
- and none of it is visible without opening 125 PDFs by hand

**Both pictures are true at once.** The instrument exists; its function is unmeasured. Four years from 2030 and the goals are off track in part because we are measuring documents rather than capability, and the layer where response actually happens is not instrumented at all.

**HubNode operates in the gap between the instrument and its function.** That is the alignment claim, and it is the honest one.

---

## 4. Primary alignment

### Sendai Framework — the correct anchor

SDG targets 11.b and 13.1 both explicitly reference the **Sendai Framework for Disaster Risk Reduction 2015–2030**, which New Zealand has endorsed. Two parts of Sendai describe this product almost verbatim:

**Target G** — *substantially increase the availability of and access to multi-hazard early warning systems and disaster risk information and assessments to the people.*

This is what the system does, and it is demonstrable rather than aspirational: multiple hazard classes aggregated, resolved against a specific community's own plan, delivered to the people who turn up, with provenance and age attached to every claim.

**Priority 4** — *enhancing disaster preparedness for effective response.* The door flow, the role catalogue and the task lists are preparedness converted into response, at the moment of decision.

Leading with Sendai rather than a goal number also signals that the mapping is derived rather than retrofitted.

### SDG 11 — Sustainable Cities and Communities

**11.b** — *implement holistic disaster risk management at all levels.* The phrase "at all levels" is the one that matters: the community hub **is** a level, and it is the level the indicator does not reach.

**11.5** — reduce deaths, people affected and economic losses from disasters, *"with a focus on protecting the poor and people in vulnerable situations."*

Our reading of "protecting" includes protecting information *about* vulnerable people. The plans name aged residential care facilities, social housing complexes, medical centres and early-childhood settings. We gated 940 of them from the public view — and then found that **919 of those 940 names appear verbatim in the plan prose of their own hub**, meaning the gate on structured data did nothing once plan text was retrieved. The redaction had to move onto the retrieval path as well. That is target 11.5 taken literally rather than cited.

### SDG 13 — Climate Action

**13.1** — *strengthen resilience and adaptive capacity to climate-related hazards and natural disasters.* The target text describes the product well. Its indicators (13.1.1 casualties, 13.1.2 national strategies, 13.1.3 local government strategies) cannot see it. State both halves; the gap is the contribution.

### SDG 16 — Peace, Justice and Strong Institutions

**16.10** — public access to information. **16.6** — effective, accountable and transparent institutions.

Indicator 16.10.2 concerns legal guarantees of access to information, and New Zealand scores well on it — the Official Information Act exists. Yet the single most operationally decisive fact in an emergency is not obtainable by machine, the national alerting feed's URL is unpublished, and the authoritative regional status page for 500,000 people is hand-typed. The law is in place; access, in practice, is not. Same pattern as 11.b.2, in a different domain.

**Challenge lanes claimed: People (primary), Peace, Partnership.** Not Planet, not Prosperity.

---

## 5. Supporting alignment

| Goal | Target | Contribution |
|---|---|---|
| **1** No Poverty | 1.5 — build the resilience of the poor and those in vulnerable situations, reduce their exposure to climate-related extreme events and disasters | The direct parallel to 11.5, and the third target sharing the local-DRR-strategy indicator (§3). Two contributions: a usable operational picture at the hub layer improves the resilience of vulnerable residents precisely when official response is stretched; and the gating of aged-care, social housing, medical and early-childhood sites — including forcing redaction onto the retrieval path — is a literal reading of protecting people in vulnerable situations. |
| **4** Quality Education | 4.4 — relevant skills; indicator 4.4.1 measures ICT skills | Just-in-time capability at the point of decision, not formal education. The original problem the mayors raised was digital and data governance capability. Honest but secondary. |
| **9** Industry, Innovation, Infrastructure | 9.1 — resilient infrastructure | Digital infrastructure counts; this is the layer that makes existing physical-infrastructure data usable. |
| **10** Reduced Inequalities | 10.2 — inclusion irrespective of status | A local node with no subscription means a rural volunteer hub gets the same operational picture as a resourced city EOC. A mechanism, not a slogan. |
| **17** Partnerships | 17.16, 17.17 | Engine open source, CAP standard, built on material the region had already written. The corpus stays with the agency accountable for it. |
| **3** Good Health and Well-being | 3.d — capacity for early warning and risk reduction | Early warning is named in the target text. Available if asked. |

### Considered and deliberately not claimed

Recorded so the reasoning is available if a judge asks why an obvious-looking goal is absent.

| Not claimed | Why |
|---|---|
| **13.3** — education, awareness-raising and capacity on climate adaptation and early warning | Appealing at target level, but indicator **13.3.1** measures *"extent to which global citizenship education and education for sustainable development are mainstreamed in national education policies, curricula, teacher education and student assessment."* That is formal schooling. Claiming it would repeat the weakness that demoted 4.4. |
| **16.7** — responsive, inclusive, participatory decision-making | The door flow helps volunteers organise themselves, but the product is not about formal institutional decision-making. A stretch. |
| **8** — decent work and economic growth | Defensible in conversation, does not earn a slide. |
| **5, 6, 7, 14, 15**, and health targets beyond 3.d | No honest fit, or they would require the outcome claims we refuse in §7. |

---

## 6. What we measure

Three measures, all computable, none of them an official indicator.

**1 · Currency of community-level response plans.**
Proportion of registered community emergency facilities with a published plan (**91%**), and with a plan reviewed within a stated window (**74%** at 24 months). This is a **proposed community-level companion** to indicator 11.b.2 — *not* 11.b.2 itself, which counts local governments rather than community facilities. Computed in seconds from public sources.

*Method note, to be stated whenever the figure is used:* the 24-month currency threshold is **ours**. WREMO publishes no review cycle. The 91% figure requires no assumption; the 74% figure does.

**2 · Time from national signal to hub-actionable instruction.**
Baseline today: no automated path exists. The path runs through a human noticing a website.

**3 · Machine-readability of authoritative emergency sources.**
A count, with a measured baseline: declaration status — none; tsunami warnings — none; fire danger — none; NEMA CAP feed — exists, URL unpublished.

---

## 7. What we do not claim

Stated plainly, because the alternative is being caught.

- **No outcome claims.** Every SDG disaster indicator is an outcome measure — deaths, people affected, economic loss. Two days, no deployment, no validation. We claim none of them and do not gesture at them.
- **We do not report indicator 11.b.2 or 13.1.3.** Our measure sits a level below what those indicators count.
- **The 24-month threshold is our assumption**, and the "ageing" cohort is mostly 2024 plans sitting just past it.
- **Neighbour relationships shown in the running demo are geometric** (nearest four), not parsed from the plans' named neighbours. The plans do name four neighbouring hubs each; our text extraction of them is not yet reliable enough to stand behind.
- **WREMO permission is requested, not granted** (6 August). Anything described as partnership is intent.
- **This is advisory. The human decides.** Before it could be authoritative it needs replay validation against historical events, scale testing across all 125 hubs, a deployment path with rollback, and a runbook for the day it is wrong. The architecture was built to survive that process rather than to be thrown away by it.

---

## 8. What we would need

Not funding. Three things, all of which are policy rather than product:

1. **Publish the state-of-emergency declaration as data.** One endpoint. It changes the national picture and costs almost nothing.
2. **Publish the NEMA CAP feed URL** that already exists and is already described as publicly available.
3. **Adopt a community-level currency measure as a national supplementary indicator** — the proportion of registered community emergency facilities with a current response plan. The instrument-level indicator is green and will stay green. This one would show whether the system works at the layer where response happens. We can compute it today, from public sources, for any region that publishes its plans.

Plus, to go further than a prototype: an open licence on hub guide material so every region can build on what Wellington has already written, and one CDEM group willing to pilot.

---

## 9. Verification status

**Verified against source, 5–6 August 2026:** all hub and plan counts, plan review dates, asset classifications, feed availability and licensing terms. Recorded in `verified-findings.md`.

**Verified against published definitions:** the wording and computation of indicator 11.b.2; the existence of 16 regional CDEM Groups; the statutory requirement for CDEM Group Plans; Auckland's Group Plan intended for 2016–2021 remaining in force.

**Not verified — do not assert:** whether Stats NZ or NEMA publishes an 11.b.2 figure for New Zealand, and what value; the formal review cycle for CDEM Group Plans; the precise section of the CDEM Act 2002 requiring Group Plans. Phrase these as "likely at or near 100% by construction" rather than as a reported statistic.

---

**Sources**

- [SDG indicator 11.b.2 metadata — UN Statistics Division](https://unstats.un.org/sdgs/metadata/files/Metadata-11-0b-02.pdf)
- [SDG indicator 13.1.3 — UNEP](https://sdgs.unep.org/article/sdg-indicator-1313)
- [SDG indicator 1.5.4 — UNEP](https://sdgs.unep.org/article/sdg-indicator-154)
- [Indicator 1.5.4 wording — UNECE](https://w3.unece.org/SDG/en/Indicator?id=187)
- [SDG indicator 13.3.1 — UNEP](https://sdgs.unep.org/article/sdg-indicator-1331)
- [Auckland Council CDEM Group Plan, Part 2 — Office of the Auditor-General](https://ao.parliament.nz/2023/auckland-council/part2.htm)
- [CDEM Group Plans — National Emergency Management Agency](https://www.civildefence.govt.nz/strategy-capability/plans-strategies/cdem-group-plans)
- [Civil Defence Emergency Management Act 2002 — NZ Legislation](https://www.legislation.govt.nz/act/public/2002/0033/latest/whole.html)
- [Community Emergency Hubs — WREMO](https://www.wremo.nz/get-ready/community-ready/community-emergency-hubs)
- [Community Emergency Hubs in the Wellington Region — GWRC Open Data](https://data-gwrc.opendata.arcgis.com/datasets/0c865aef23ec4bbca358d335e5c307cb)

*Attribution required on screen: hub locations © Greater Wellington Regional Council (CC BY-NC-ND 4.0); Hub Guide and Community Response Plans © WREMO, all rights reserved.*
