# CHORD — 5-minute pitch script

Community Hub Operations & Response Desk

**Presenter split**

- Alex: personal story and hook.
- Joshua: problem to solve and first half of the big idea.
- Leon: live demo narration, trust/safety, future impact and SDG alignment.

Target: 4:55. Slides stay sparse; scripts live in notes.

## Slide 1: Alex’s story

**Presenter:** Alex  
**Timing:** 0:00–0:55

Two minutes past midnight. November 14th, 2016.

The Kaikōura earthquake — magnitude 7.8 — hits.

I’m safe. I only dropped my laptop.

But what about everybody else?

And I realise I don’t know four things:

Who might need help?
How can I reach them?
Who is available to help?
And what can I do?

That night, I had no answers.

(pause)

Tonight, I do.

This is CHORD — Community Hub Operations & Response Desk.

An AI-powered emergency desk that helps a community coordinate when it matters most — even when the network is down.

Let us show you.
## Slide 2: Problem

**Presenter:** Joshua  
**Timing:** 0:55–1:45

I’ll pick up from Alex’s four questions.

He assumed that was him being unprepared. It wasn’t.

New Zealand’s answer is community emergency hubs — 126 in the Wellington region. They are community-run, not official command posts. Roles are allocated by agreement between whoever turns up. What a hub has is a VHF radio, a whiteboard, and a guide.

Here is the data. Of the people who evacuated after Kaikōura, only about a third got out inside the ten minutes they had. Two thirds drove, when the advice is to walk. Alex’s confusion wasn’t unusual — it was typical.

So the problem is not that the expertise is missing. It is locked in PDFs, live feeds, local memory, and people’s heads — exactly when a community needs it most.

Coordination is the gap.
## Slide 3: Big idea

**Presenter:** Joshua  
**Timing:** 1:45–2:35

Every hub already has a response plan — its water tank, its neighbouring hubs, and its key community sites. They are PDFs, and nobody opens a PDF in an earthquake.

So we made the plan read the feeds.

CHORD brings together local plans, live hazard feeds, and the people walking through the door. It turns them into a live board, role assignment, next tasks, answers from the playbook, and a printable fallback page.

Here is the important AI boundary. Rules decide whether a hazard matters to your hub. AI decides what to say about it. People decide what to do.

The model selects, summarises, translates, and orders tasks for one person at one moment. It cannot author an emergency instruction of its own. Every task traces back to the WREMO guide or the local hub plan.

Leon, show us what this looks like in the hub.
## Slide 4: Demo

**Presenter:** Leon  
**Timing:** 2:35–3:45

This is Newtown’s board, and every fact on it carries its source and its age.

I’ll run a real evening forward: a warning arrives, the river rises, and the posture climbs from watch to act.

Five people turn up. Instead of everybody looking for the one person who has read the guide, CHORD fills the priority roles first and hands each person their next three tasks.

Ask it a question and you get the page it came from — in English, or in Tagalog, with the same citation.

And when a feed dies, the tile degrades and says so.

That matters. The system we are replacing can be stale and never say a word. CHORD tells the hub what it knows, where it came from, and when it stopped knowing.
## Slide 5: Trust by design

**Presenter:** Leon  
**Timing:** 3:45–4:15

This is where we are deliberately conservative.

Emergency AI must know its limits. Every tile says where it came from and how old it is. AI advises, but a human coordinator makes the decision. The model cannot invent a new emergency instruction. It only selects from the guide and the hub plan.

And it is local-first because the network may fail. CHORD degrades from live feeds, to a cached briefing, to a printable page, to a radio handoff.

We kept AI out of deciding whether an emergency is happening. You cannot audit a model’s judgement about that. You can audit a source, a page number, and a human decision.
## Slide 6: Future impact and SDGs

**Presenter:** Leon  
**Timing:** 4:15–4:55

Here is the global impact gap in one picture.

The official measure of disaster resilience is effectively the same indicator under several global frameworks: Sendai Target G and the Sustainable Development Goals. It asks whether local government has disaster risk-reduction plans. In New Zealand, every emergency management group is legally required to hold one, so the number reads one hundred percent.

But one level down — where people actually turn up after the shaking — the hub layer is invisible. We found 114 of 126 hubs with a published plan. Those plans range from current to years old, and nobody reports that number. We computed it from public sources in seconds.

That is CHORD’s SDG contribution: SDG 11.b for local disaster risk planning, SDG 13.1 for resilience and adaptive capacity, SDG 16.10 for public access to timely information, and SDG 1.5 for reducing exposure to shocks for vulnerable communities.

What do we need? Publish the declaration fields NEMA already holds. Let the community layer report into EMS-OS. And measure whether the plans at that layer are current.

Wellington is a wealthy capital with 114 published plans. The places that need this most often have neither. Scaling CHORD is adapters, not rewrites — one emergency management group at a time.

The hub playbook already exists. We made it read the news.

## Live demo recording checklist

Leon narrates these four beats live over the recording:

1. Newtown board: every tile shows source and age.
2. Replay evening: warning arrives, river rises, posture changes.
3. Walk-ins: CHORD assigns priority roles and next tasks.
4. Ask AI, then kill a feed: answer cites the guide; stale feed degrades visibly.

## GitHub naming note

Working draft name KEA should be replaced with CHORD in user-facing UI, deck screenshots, and demo narration before recording. Keep internal package names only if renaming would risk breaking the demo.

## Reserve Q&A lines

**Isn’t this just a dashboard?** A dashboard shows data. CHORD hands a named person their next tasks, from their own hub plan and the WREMO guide. Delete the plan and the product stops working.

**What if the AI is wrong?** It cannot author emergency instructions. It selects from the guide and hub plan, every task traces to a source, and humans decide what to do.
