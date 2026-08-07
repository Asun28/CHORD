import Foundation

// MARK: - Status / feed answers from scenario + live drivers
/// Deterministic floor for "latest quakes", weather, power, roads, etc.
/// Never invents magnitudes or events not present in the supplied rows.

enum StatusAnswerBuilder {
 struct Built {
  var answer: String
  var citations: [CitationVO]
  var unknowns: [String]

  var asGrounded: GroundedAnswerBuilder.Built {
   GroundedAnswerBuilder.Built(answer: answer, citations: citations, unknowns: unknowns)
  }
 }

 /// Build a grounded status answer. Prefer scenario monitor rows for the
 /// matching feed group; fall back to live CAP drivers; never invent.
 static func build(
  question: String,
  hubName: String,
  drivers: [SituationDriver],
  scenario: ScenarioSnapshot
 ) -> Built {
  let q = question.lowercased()
  let groups = matchingGroups(for: q)
  var lines: [String] = []
  var citations: [CitationVO] = []
  var unknowns: [String] = []

  lines.append("**\(hubName)** · situation relay")
  if scenario.hasContent {
   if let name = scenario.eventName {
    lines.append("Demo event: \(name)\(scenario.eventStatus.map { " (\($0))" } ?? "")")
   }
   lines.append(scenario.notice)
  }

  var anyRow = false

  for group in groups {
   let demoRows = scenario.monitorItems.filter { group.feeds.contains($0.feed.lowercased()) }
   let liveRows = drivers.filter { driverMatches($0, group: group) }

   if demoRows.isEmpty && liveRows.isEmpty {
    continue
   }
   anyRow = true
   lines.append("")
   lines.append("### \(group.label)")

   if !demoRows.isEmpty {
    lines.append("From the demo scenario monitor (fictional, for practice):")
    for row in demoRows {
     lines.append("- **\(row.title)** · \(row.time) · \(row.severity)")
     if !row.detail.isEmpty {
      lines.append("  \(row.detail)")
     }
     lines.append("  Source: \(row.feed) · id \(row.id) · demo")
     citations.append(
      CitationVO(
       kind: .observation,
       sourceRef: "Demo monitor · \(row.feed) · \(row.id)",
       detail: row.title
      )
     )
    }
   }

   if !liveRows.isEmpty {
    lines.append(demoRows.isEmpty ? "From live / fixture CAP drivers:" : "Also from live / fixture CAP drivers:")
    for d in liveRows.prefix(8) {
     lines.append("- **\(d.headline)** · \(d.ageLabel) · \(d.trustTier.label)")
     lines.append("  \(d.attribution)\(d.isStale ? " · may be stale" : "")")
     citations.append(
      CitationVO(
       kind: .observation,
       sourceRef: d.observationID,
       detail: d.headline
      )
     )
    }
   }
  }

  // Board snapshot when asking "what is happening" broadly
  if scenario.hasContent, wantsBoard(q) || (!anyRow && groups.contains(where: { $0.id == "general" })) {
   let sit = scenario.sitItems.prefix(8)
   if !sit.isEmpty {
    lines.append("")
    lines.append("### Situation board (demo)")
    for row in sit {
     lines.append("- \(row.whatsHappening) · \(row.ts) · \(row.sourceType)")
     if !row.ourResponse.isEmpty {
      lines.append("  Hub response: \(row.ourResponse)")
     }
     citations.append(
      CitationVO(
       kind: .observation,
       sourceRef: "Demo sit · \(row.id)",
       detail: row.whatsHappening
      )
     )
    }
    anyRow = true
   }
  }

  if !anyRow {
   lines.append("")
   lines.append(
    "No matching feed or board rows are loaded for that question right now."
   )
   if !scenario.enabled {
    lines.append(
     "Companion demo scenario is off. Turn on **Use Companion demo scenario** in Settings to load the M7.1 practice feeds, or advance Replay for fixture CAP."
    )
   } else if scenario.monitorItems.isEmpty {
    lines.append("Demo scenario is on but the seed monitor list is empty.")
    unknowns.append("Demo scenario monitor empty")
   } else {
    lines.append(
     "The demo monitor has \(scenario.monitorItems.count) items, but none matched this question's feed filters."
    )
   }
   if drivers.isEmpty {
    unknowns.append("No live CAP drivers for this hub")
   }
  } else {
   lines.append("")
   lines.append(
    "Do not invent additional magnitudes, times, or locations beyond the rows above."
   )
  }

  var seen = Set<String>()
  let unique = citations.filter { seen.insert($0.id).inserted }
  return Built(answer: lines.joined(separator: "\n"), citations: unique, unknowns: unknowns)
 }

 // MARK: - Group matching

 struct FeedGroup {
  var id: String
  var label: String
  var feeds: Set<String>
  var keywords: [String]
 }

 static let groups: [FeedGroup] = [
  FeedGroup(
   id: "quake",
   label: "Earthquakes and aftershocks (GeoNet)",
   feeds: ["geonet"],
   keywords: [
    "quake", "earthquake", "aftershock", "aftershocks", "shaking", "magnitude",
    "seismic", "felt",
   ]
  ),
  FeedGroup(
   id: "weather",
   label: "Weather (MetService)",
   feeds: ["metservice"],
   keywords: ["weather", "rain", "wind", "storm", "southerly", "forecast", "gale"]
  ),
  FeedGroup(
   id: "tsunami",
   label: "National alerts (NEMA)",
   feeds: ["nema"],
   keywords: ["tsunami", "nema", "national alert", "emergency mobile"]
  ),
  FeedGroup(
   id: "water",
   label: "Water faults",
   feeds: ["wwater", "water"],
   keywords: ["water main", "pipe", "boil water", "wellington water", "water fault"]
  ),
  FeedGroup(
   id: "power",
   label: "Electricity outages",
   feeds: ["outages", "power"],
   keywords: ["power", "outage", "electricity", "generator", "blackout"]
  ),
  FeedGroup(
   id: "roads",
   label: "Roads (NZTA)",
   feeds: ["nzta", "roads"],
   keywords: ["road", "highway", "closure", "slip", "traffic", "nzta", "parade"]
  ),
  FeedGroup(
   id: "hub",
   label: "Hub reports",
   feeds: ["hub", "hubs"],
   keywords: ["hub report", "this hub", "our report"]
  ),
 ]

 private static func matchingGroups(for q: String) -> [FeedGroup] {
  let hit = groups.filter { g in g.keywords.contains { q.contains($0) } }
  if !hit.isEmpty { return hit }
  // Broad status language with no specific feed: all groups that have data will be filtered later
  if wantsBoard(q) || matchesStatusLanguage(q) {
   return [FeedGroup(
    id: "general",
    label: "All monitor feeds",
    feeds: Set(groups.flatMap(\.feeds)),
    keywords: []
   )]
  }
  return groups
 }

 private static func wantsBoard(_ q: String) -> Bool {
  [
   "what is happening", "what's happening", "whats happening",
   "situation board", "on the board", "our situation",
  ].contains { q.contains($0) }
 }

 private static func matchesStatusLanguage(_ q: String) -> Bool {
  [
   "latest", "current", "right now", "just now", "any ", "status",
   "update", "updates", "warning", "warnings", "report", "closed",
  ].contains { q.contains($0) }
 }

 private static func driverMatches(_ d: SituationDriver, group: FeedGroup) -> Bool {
  let sid = d.sourceID.lowercased()
  if group.feeds.contains(where: { sid.contains($0) }) { return true }
  switch group.id {
  case "quake": return d.hazardClass == .quake
  case "weather": return d.hazardClass == .weather
  case "roads": return d.hazardClass == .road
  case "water", "power": return d.hazardClass == .other || d.headline.lowercased().contains(group.id)
  default:
   return group.feeds.contains(where: { sid.contains($0) })
  }
 }
}
