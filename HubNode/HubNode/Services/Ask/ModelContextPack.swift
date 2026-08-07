import Foundation

/// Explicit context bundle sent to the local model.
/// Structured hub facts first; plan prose second. So asset questions cannot
/// be answered only from "not available" plan headings.
enum ModelContextPack {
 static func build(
 question: String,
 intent: AskIntent,
 facts: HubFactsVO,
 passages: [RetrievedPassageVO],
 groundedAnswer: String,
 tasks: [TaskLineVO] = [],
 scenario: ScenarioSnapshot = .empty
 ) -> [String] {
 var parts: [String] = []

 parts.append(
 """
 ## THIS HUB (you are answering for this hub only. You ARE the playbook)
 Name: \(facts.name)
 Address: \(facts.address)
 Territorial authority: \(facts.taName)
 View: \(facts.viewLevel.title)
 Posture (rule-computed, do not change): \(facts.posture.title)
 Plan currency: \(facts.hasPublishedPlan ? "reviewed \(facts.planReviewedOn ?? "unknown") · \(facts.planCurrency.rawValue)" : "no published plan")
 Intent: \(intent.rawValue)
 """
 )

 // Never lead with a URL. Plan link is citation only, not an instruction.
 if let url = facts.planURL {
 parts.append("## SOURCE LINK (citation only. Do NOT tell the user to go read this PDF)\n\(url)")
 }

 if scenario.hasContent {
  var sitLines: [String] = []
  if let name = scenario.eventName {
   sitLines.append("Event: \(name)\(scenario.eventStatus.map { " (\($0))" } ?? "")")
  }
  sitLines.append(scenario.notice)
  if !scenario.monitorItems.isEmpty {
   sitLines.append("Monitor rows:")
   for row in scenario.monitorItems.prefix(24) {
    sitLines.append(
     "- [\(row.feed)] \(row.time) · \(row.severity) · \(row.title) (id \(row.id), demo)"
    )
    if !row.detail.isEmpty {
     sitLines.append("  detail: \(row.detail.truncated(to: 280))")
    }
   }
  }
  if !scenario.sitItems.isEmpty {
   sitLines.append("Situation board:")
   for row in scenario.sitItems.prefix(12) {
    sitLines.append("- \(row.ts) · \(row.whatsHappening) [\(row.sourceType)]")
   }
  }
  parts.append(
   """
   ## DEMO SCENARIO SITUATION (fictional practice data · structured facts)
   When the question asks for latest quakes, aftershocks, weather, power, roads, water faults, or board status, answer FROM THESE ROWS.
   List times, titles, and source ids. Do NOT invent extra magnitudes or events.
   Do NOT replace a feed status answer with a hub setup checklist unless the user asked how to set up.
   \(sitLines.joined(separator: "\n"))
   """
  )
 }

 if !facts.drivers.isEmpty {
 let lines = facts.drivers.prefix(8).map {
 "- \($0.headline) · \($0.ageLabel) · \($0.trustTier.label) · \($0.attribution)"
 }.joined(separator: "\n")
 parts.append("## LIVE / FIXTURE CAP DRIVERS MATCHING THIS HUB\n\(lines)")
 }

 // Status questions: skip setup catalogue so the model cannot pivot to wind checklists
 if intent == .status {
  parts.append(
   """
   ## STATUS QUESTION RULES
   Answer only with MONITOR / SITUATION / LIVE DRIVER facts above.
   Prefer demo scenario rows for earthquakes and aftershocks when present.
   If both demo and live rows exist, list both and label which is which.
   If nothing matches, say so. Never invent GeoNet events.
   """
  )
  parts.append(
   """
   ## GROUNDED BRIEF (app-assembled status answer)
   \(groundedAnswer.truncated(to: 3200))
   """
  )
  return parts
 }

 // Setup / open: explicit numbered-ready task list the model must use
 if intent == .setup || intent == .openDecision || !tasks.isEmpty {
 let steps = (tasks.isEmpty ? SetupFallback.tasks : tasks)
 let lines = steps.enumerated().map { i, t in
 "\(i + 1). \(t.text) [role: \(t.roleCode) · \(t.phase.title) · \(t.sourceRef)]"
 }.joined(separator: "\n")
 parts.append(
 """
 ## SETUP / OPENING STEPS (from WREMO Hub Guide catalogue. Use these as the answer)
 You must turn these into a clear numbered checklist for volunteers at \(facts.name).
 Do NOT replace this list with "check the CRP PDF" or "follow standard procedures".
 You may interleave hub-specific facts (address, water tank, neighbours) from other sections.
 \(lines)
 """
 )
 }

 let assetQuestion = intent == .place || isAssetQuestion(question)
 if assetQuestion || intent == .setup || !facts.assets.isEmpty {
 if facts.assets.isEmpty {
 parts.append(
 """
 ## AVAILABLE ASSETS AT THIS HUB
 (none loaded for this view)
 Restricted withheld: \(facts.restrictedWithheldCount)
 """
 )
 } else {
 let ordered = facts.assets.sorted { a, b in
 rank(a.kind) < rank(b.kind) || (rank(a.kind) == rank(b.kind) && a.name < b.name)
 }
 let lines = ordered.prefix(50).map { "- [\($0.kind)] \($0.name)" }.joined(separator: "\n")
 parts.append(
 """
 ## AVAILABLE ASSETS AT THIS HUB
 If this list is non-empty, quote it when asked what is available. Never say none are listed.
 \(lines)
 Restricted facilities withheld from this view: \(facts.restrictedWithheldCount)
 """
 )
 }
 }

 if !facts.neighbours.isEmpty {
 let lines = facts.neighbours.map {
 "- \($0.name) · \($0.posture.title)"
 }.joined(separator: "\n")
 parts.append("## NEIGHBOURING HUBS\n\(lines)")
 }

 if intent == .role || intent == .setup {
 let lines = facts.roles.map {
 let p = $0.priorityRank <= 4 ? " (priority \($0.priorityRank))" : ""
 return "- \($0.name)\(p): \($0.roleDescription)"
 }.joined(separator: "\n")
 parts.append("## OFFICIAL ROLES\n\(lines)")
 }

 parts.append(
 """
 ## GROUNDED BRIEF (app-assembled)
 \(groundedAnswer.truncated(to: 2800))
 """
 )

 if !passages.isEmpty {
 let lines = passages.prefix(8).enumerated().map { i, p in
 let origin = p.origin == .hubPlan ? "THIS HUB PLAN" : "REGIONAL GUIDE"
 return "[\(i + 1) · \(origin) · \(p.section)]\n\(p.text.truncated(to: 1200))"
 }.joined(separator: "\n\n")
 parts.append(
 """
 ## PLAN / GUIDE PASSAGES
 Use these to enrich the checklist with hub-specific detail (kit location, water, spaces).
 Contingency headings like "if facilities are not available" are not a list of missing assets.
 \(lines)
 """
 )
 }

 return parts
 }

 static func isAssetQuestion(_ question: String) -> Bool {
 let q = question.lowercased()
 let keys = [
 "asset", "assets", "resource", "resources", "facility", "facilities",
 "equipment", "supplies", "available", "what do we have", "what have we",
 "water tank", "kit", "venue", "places", "where can", "inventory", "stock",
 ]
 return keys.contains { q.contains($0) }
 }

 private static func rank(_ kind: String) -> Int {
 switch kind {
 case "emergency_water": return 0
 case "public_place": return 1
 case "restricted_facility": return 2
 default: return 3
 }
 }
}
