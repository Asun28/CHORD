import Foundation

// MARK: - Companion demo seed
/// Loads hub-companion/seed/v0.3 JSON from the app bundle.
/// Provides Companion-only domains (needs, sit_items, runbooks, i18n) while live CAP drives posture.

@MainActor
final class CompanionSeedStore {
 static let shared = CompanionSeedStore()

 private(set) var rawJSON: Data?
 private(set) var root: [String: Any]?
 private(set) var loadMessage: String = "Not loaded"

 var isLoaded: Bool { root != nil }

 func loadIfNeeded() {
  if root != nil { return }
  reload()
 }

 func reload() {
  rawJSON = nil
  root = nil
  guard let data = Self.locateSeedData() else {
   loadMessage = "Seed file not found in bundle"
   return
  }
  rawJSON = data
  do {
   let obj = try JSONSerialization.jsonObject(with: data)
   guard let dict = obj as? [String: Any] else {
    loadMessage = "Seed root is not an object"
    return
   }
   root = dict
   loadMessage = "Loaded companion seed (\(data.count) bytes)"
  } catch {
   loadMessage = "Seed parse failed: \(error.localizedDescription)"
  }
 }

 func array(forKey key: String) -> [[String: Any]] {
  loadIfNeeded()
  return (root?[key] as? [[String: Any]]) ?? []
 }

 func object(forKey key: String) -> [String: Any]? {
  loadIfNeeded()
  return root?[key] as? [String: Any]
 }

 func sitItems() -> [CompanionSitItemDTO] {
  array(forKey: "sit_items").compactMap { row in
   guard let id = row["id"] as? String else { return nil }
   return CompanionSitItemDTO(
    id: id,
    ts: string(row["ts"]),
    location: string(row["location"]),
    whats_happening: string(row["whats_happening"]),
    our_response: string(row["our_response"]),
    priority: string(row["priority"]),
    source_type: string(row["source_type"]),
    confirmed: (row["confirmed"] as? Bool) ?? false
   )
  }
 }

 func seedTasks() -> [CompanionTaskDTO] {
  array(forKey: "tasks").compactMap { row in
   guard let id = row["id"] as? String else { return nil }
   let how = row["how"] as? [String]
   return CompanionTaskDTO(
    id: id,
    template_id: id,
    role_code: string(row["role"]),
    text: string(row["title"]).isEmpty ? string(row["how"]) : string(row["title"]),
    source_ref: string(row["ref"]),
    status: string(row["status"]),
    assignee_name: (row["assignee"] as? String).flatMap { $0.isEmpty ? nil : $0 },
    created_at: string(row["when"]),
    priority: string(row["priority"]),
    how: how,
    when: string(row["when"]),
    where_text: string(row["where"]),
    title: string(row["title"])
   )
  }
 }

 func needs() -> [CompanionNeedDTO] {
  array(forKey: "needs").compactMap { row in
   guard let id = row["id"] as? String else { return nil }
   return CompanionNeedDTO(
    id: id,
    ts: string(row["ts"]),
    description: string(row["description"]),
    name: string(row["name"]),
    contact: optionalString(row["contact"]),
    category: string(row["category"]),
    life_threatening: (row["life_threatening"] as? Bool) ?? false,
    status: string(row["status"]),
    routing: optionalString(row["routing"])
   )
  }
 }

 func offers() -> [CompanionOfferDTO] {
  array(forKey: "offers").compactMap { row in
   guard let id = row["id"] as? String else { return nil }
   return CompanionOfferDTO(
    id: id,
    ts: string(row["ts"]),
    description: string(row["description"]),
    name: string(row["name"]),
    contact: optionalString(row["contact"]),
    category: string(row["category"]),
    status: string(row["status"])
   )
  }
 }

 func matches() -> [[String: String]] {
  array(forKey: "matches").map { row in
   var out: [String: String] = [:]
   for (k, v) in row {
    out[k] = string(v)
   }
   return out
  }
 }

 func publicInfoItems() -> [CompanionPublicInfoItemDTO] {
  array(forKey: "pub_info_items").compactMap { row in
   guard let id = row["id"] as? String else { return nil }
   return CompanionPublicInfoItemDTO(
    id: id,
    ts: string(row["ts"]),
    source: string(row["source"]),
    message: string(row["message"])
   )
  }
 }

 func roleRunbooks() -> CompanionRunbooksDTO {
  let obj = object(forKey: "role_runbooks") ?? [:]
  var roles: [String: [String]] = [:]
  var note = ""
  for (k, v) in obj {
   if k == "note" {
    note = string(v)
    continue
   }
   if let list = v as? [String] {
    roles[k] = list
   } else if let list = v as? [Any] {
    roles[k] = list.map { string($0) }
   }
  }
  return CompanionRunbooksDTO(note: note, roles: roles)
 }

 func monitorFeeds() -> [CompanionFeedDTO] {
  let mon = object(forKey: "monitor") ?? [:]
  let feeds = mon["feeds"] as? [[String: Any]] ?? []
  return feeds.compactMap { row in
   guard let id = row["id"] as? String else { return nil }
   return CompanionFeedDTO(
    id: id,
    name: string(row["name"]),
    endpoint: optionalString(row["endpoint"]),
    licence: optionalString(row["licence"]),
    poll: optionalString(row["poll"]),
    fetched: optionalString(row["fetched"]),
    paused: false,
    live: false,
    attribution: optionalString(row["licence"])
   )
  }
 }

 func monitorItems() -> [CompanionMonitorItemDTO] {
  let mon = object(forKey: "monitor") ?? [:]
  let items = mon["items"] as? [[String: Any]] ?? []
  return items.compactMap { row in
   guard let id = row["id"] as? String else { return nil }
   return CompanionMonitorItemDTO(
    id: id,
    feed: string(row["feed"]),
    severity: string(row["severity"]),
    time: string(row["time"]),
    title: string(row["title"]),
    detail: string(row["detail"]),
    lat: row["lat"] as? Double,
    lng: row["lng"] as? Double,
    source: "seed",
    is_stale: false
   )
  }
 }

 /// Ask-facing scenario snapshot when demo mode is on.
 func scenarioSnapshot(enabled: Bool) -> ScenarioSnapshot {
  guard enabled else { return .empty }
  loadIfNeeded()
  let event = object(forKey: "event") ?? [:]
  let eventName = optionalString(event["name"])
  let eventStatus = optionalString(event["status"])
  let monitor = monitorItems().map {
   ScenarioMonitorLine(
    id: $0.id,
    feed: $0.feed,
    severity: $0.severity,
    time: $0.time,
    title: $0.title,
    detail: $0.detail,
    source: "demo"
   )
  }
  let sit = sitItems().map {
   ScenarioSitLine(
    id: $0.id,
    ts: $0.ts,
    location: $0.location,
    whatsHappening: $0.whats_happening,
    ourResponse: $0.our_response,
    priority: $0.priority,
    sourceType: $0.source_type
   )
  }
  return ScenarioSnapshot(
   enabled: true,
   eventName: eventName,
   eventStatus: eventStatus,
   notice: "Demo scenario data is fictional. Relayed for hub practice only. Not a live official feed.",
   monitorItems: monitor,
   sitItems: sit
  )
 }

 /// Map seed / Companion role display names to HubNode catalogue codes.
 func roleCode(forDisplayName name: String) -> String? {
  let n = name.lowercased()
  let map: [(String, String)] = [
   ("hub supervisor", "hub_supervisor"),
   ("supervisor", "hub_supervisor"),
   ("information coordination", "information_coord"),
   ("information", "information_coord"),
   ("public information", "public_information"),
   ("public info", "public_information"),
   ("reception", "reception"),
   ("needs and offers", "needs_and_offers"),
   ("needs", "needs_and_offers"),
   ("community space", "community_space"),
   ("communications", "communications"),
   ("facility maintenance", "facility_maintenance"),
   ("facility", "facility_maintenance"),
  ]
  for (key, code) in map where n.contains(key) {
   return code
  }
  return nil
 }

 private func string(_ any: Any?) -> String {
  if let s = any as? String { return s }
  if let n = any as? NSNumber { return n.stringValue }
  return ""
 }

 private func optionalString(_ any: Any?) -> String? {
  let s = string(any)
  return s.isEmpty ? nil : s
 }

 private static func locateSeedData() -> Data? {
  let names = ["demo-seed-data-v0.3", "demo-seed-data"]
  for name in names {
   let urls: [URL?] = [
    Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "WebUI"),
    Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources/WebUI"),
    Bundle.main.url(forResource: name, withExtension: "json"),
   ]
   for url in urls {
    if let url, let data = try? Data(contentsOf: url) { return data }
   }
  }
  if let all = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
   if let url = all.first(where: { $0.lastPathComponent.contains("demo-seed-data") }),
    let data = try? Data(contentsOf: url) {
    return data
   }
  }
  return nil
 }
}
