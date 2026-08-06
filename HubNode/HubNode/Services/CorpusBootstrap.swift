import Foundation
import SwiftData

// MARK: - Flow: corpus load
/// Two layers: (1) `loadMapItems()` → value types for MapKit (hubs.json preferred);
/// (2) SwiftData seed for board/Ask (hubs, assets, roles, task catalogue, guide).
/// Map works even if SwiftData seed is incomplete. Attribution is mandatory on UI.

enum CorpusBootstrapError: Error, LocalizedError {
 case missingResource(String)
 case parse(String)
 case emptyHubs

 var errorDescription: String? {
 switch self {
 case .missingResource(let n): return "Missing corpus resource: \(n)"
 case .parse(let m): return "Corpus parse error: \(m)"
 case .emptyHubs: return "hubs.csv parsed to zero rows"
 }
 }
}

enum CorpusBootstrap {
 static let attribution =
 "Hub locations © Greater Wellington Regional Council (CC BY-NC-ND 4.0). Hub Guide and Community Response Plans © WREMO, all rights reserved."

 // MARK: - Direct load (no SwiftData). Source of truth for the map

 /// Load hubs for the map. Prefers hubs.json (reliable); falls back to CSV.
 static func loadMapItems() throws -> [HubMapItem] {
 if let items = try? loadMapItemsFromJSON(), !items.isEmpty {
 return items
 }
 let items = try loadMapItemsFromCSV()
 if items.isEmpty { throw CorpusBootstrapError.emptyHubs }
 return items
 }

 private static func loadMapItemsFromJSON() throws -> [HubMapItem] {
 let url = try resourceURL("hubs", ext: "json")
 let data = try Data(contentsOf: url)
 let decoded = try JSONDecoder().decode([HubMapItemDTO].self, from: data)
 let items = decoded.map { $0.asMapItem() }
 if items.isEmpty { throw CorpusBootstrapError.emptyHubs }
 return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
 }

 private static func loadMapItemsFromCSV() throws -> [HubMapItem] {
 let neighbours = (try? loadNeighbours()) ?? [:]
 let url = try resourceURL("hubs", ext: "csv")
 let text = try String(contentsOf: url, encoding: .utf8)
 // Use Foundation's scanner-friendly line split; parse with a quote-aware reader
 var items: [HubMapItem] = []
 var header: [String] = []
 for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
 let cols = parseCSVLine(String(line))
 if index == 0 {
 header = cols.map { $0.trimmingCharacters(in: .whitespaces) }
 continue
 }
 guard cols.count >= 6 else { continue }
 var row: [String: String] = [:]
 for (i, h) in header.enumerated() where i < cols.count {
 row[h] = cols[i]
 }
 // Also bind by fixed positions in case headers mismatch
 let id = nonempty(row["slug"] ?? row["id"]) ?? nonempty(cols[safe: 0])
 let name = nonempty(row["name"]) ?? nonempty(cols[safe: 1])
 let latS = row["lat"] ?? cols[safe: 4] ?? ""
 let lonS = row["lon"] ?? cols[safe: 5] ?? ""
 guard let id, let name,
 let lat = Double(latS.trimmingCharacters(in: .whitespaces)),
 let lon = Double(lonS.trimmingCharacters(in: .whitespaces))
 else { continue }
 items.append(HubMapItem(
 id: id,
 name: name,
 taName: row["ta_name"] ?? cols[safe: 2] ?? "",
 address: row["address"] ?? cols[safe: 3] ?? "",
 latitude: lat,
 longitude: lon,
 crpURL: nonempty(row["crp_url"]),
 crpReviewedOn: nonempty(row["crp_reviewed_on"]),
 neighbourIDs: neighbours[id] ?? [],
 nAssetsPublic: Int(row["n_assets_public"] ?? "") ?? 0,
 nAssetsRestricted: Int(row["n_assets_restricted"] ?? "") ?? 0
 ))
 }
 return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
 }

 /// Quote-aware single-line CSV field split.
 private static func parseCSVLine(_ line: String) -> [String] {
 var cols: [String] = []
 var current = ""
 var inQuotes = false
 var i = line.startIndex
 while i < line.endIndex {
 let ch = line[i]
 if ch == "\"" {
 let next = line.index(after: i)
 if inQuotes && next < line.endIndex && line[next] == "\"" {
 current.append("\"")
 i = line.index(after: next)
 continue
 }
 inQuotes.toggle()
 i = line.index(after: i)
 continue
 }
 if ch == "," && !inQuotes {
 cols.append(current)
 current = ""
 i = line.index(after: i)
 continue
 }
 current.append(ch)
 i = line.index(after: i)
 }
 cols.append(current)
 return cols
 }

 // MARK: - SwiftData seed (board detail, sessions, assets)

 @MainActor
 static func seedSwiftDataIfNeeded(context: ModelContext, mapItems: [HubMapItem]) throws {
 let existing = try context.fetchCount(FetchDescriptor<Hub>())
 if existing == 0 {
 try seedSwiftData(context: context, mapItems: mapItems)
 return
 }
 // Hubs exist but supporting tables may have failed on a prior run. Top up.
 let assetCount = try context.fetchCount(FetchDescriptor<HubAsset>())
 if assetCount == 0 {
 print("HubNode: hubs present but 0 assets. Reseeding assets only")
 try seedAssetsOnly(context: context)
 }
 try ensurePlaybookSeeded(context: context)
 }

 /// Roles, task catalogue, guide chunks. Required for Ask/setup answers.
 @MainActor
 static func ensurePlaybookSeeded(context: ModelContext) throws {
 let roleCount = try context.fetchCount(FetchDescriptor<RoleDef>())
 if roleCount == 0 {
 for r in try loadRoles() { context.insert(r) }
 print("HubNode: seeded roles")
 }
 let taskCount = try context.fetchCount(FetchDescriptor<TaskTemplate>())
 if taskCount == 0 {
 let tasks = try loadTaskTemplates()
 for t in tasks { context.insert(t) }
 print("HubNode: seeded \(tasks.count) task templates")
 }
 let guideCount = try context.fetchCount(FetchDescriptor<GuideChunk>())
 if guideCount == 0 {
 let chunks = try loadGuideChunks()
 for g in chunks { context.insert(g) }
 print("HubNode: seeded \(chunks.count) guide chunks")
 }
 try context.save()
 }

 /// Attach assets to existing hub rows (by hub name match from assets.csv).
 @MainActor
 static func seedAssetsOnly(context: ModelContext) throws {
 let hubs = try context.fetch(FetchDescriptor<Hub>())
 guard !hubs.isEmpty else { return }
 let hubByID = Dictionary(uniqueKeysWithValues: hubs.map { ($0.id, $0) })
 let assets = try loadAssets(hubByID: hubByID)
 for a in assets { context.insert(a) }
 try context.save()
 print("HubNode: seeded \(assets.count) assets onto \(hubs.count) hubs")
 }

 /// Ensure one hub has its asset rows (used when opening a board).
 @MainActor
 static func ensureAssets(for hub: Hub, context: ModelContext) throws {
 if !hub.assets.isEmpty { return }
 let hubByID = [hub.id: hub]
 let assets = try loadAssets(hubByID: hubByID)
 // loadAssets matches by display name. Also try all hubs with same name
 if assets.isEmpty {
 let all = try context.fetch(FetchDescriptor<Hub>())
 let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
 let more = try loadAssets(hubByID: Dictionary(uniqueKeysWithValues: byName.map { ($0.value.id, $0.value) }))
 let forThis = more.filter { $0.hub?.id == hub.id || $0.hub?.name == hub.name }
 for a in forThis {
 if a.hub?.id != hub.id {
 a.hub = hub
 hub.assets.append(a)
 }
 context.insert(a)
 }
 try context.save()
 print("HubNode: ensured \(forThis.count) assets for \(hub.name)")
 return
 }
 for a in assets { context.insert(a) }
 try context.save()
 print("HubNode: ensured \(assets.count) assets for \(hub.name)")
 }

 @MainActor
 static func reseedSwiftData(context: ModelContext, mapItems: [HubMapItem]) throws {
 try clearAll(context: context)
 try seedSwiftData(context: context, mapItems: mapItems)
 }

 @MainActor
 private static func seedSwiftData(context: ModelContext, mapItems: [HubMapItem]) throws {
 // Hubs first. Map already works even if assets fail later
 var hubByID: [String: Hub] = [:]
 for item in mapItems {
 let hub = Hub(
 id: item.id,
 name: item.name,
 taName: item.taName,
 address: item.address,
 latitude: item.latitude,
 longitude: item.longitude,
 crpURL: item.crpURL,
 crpReviewedOn: item.crpReviewedOn,
 kitContentsJSON: "[]",
 neighbourIDs: item.neighbourIDs,
 nAssetsPublic: item.nAssetsPublic,
 nAssetsRestricted: item.nAssetsRestricted
 )
 context.insert(hub)
 hubByID[item.id] = hub
 }
 try context.save()

 // Roles + tasks (small)
 for r in try loadRoles() { context.insert(r) }
 for t in try loadTaskTemplates() { context.insert(t) }
 try context.save()

 // Guide chunks
 for g in try loadGuideChunks() { context.insert(g) }
 try context.save()

 // Assets. Large; failures are logged but don't wipe hubs
 do {
 let assets = try loadAssets(hubByID: hubByID)
 for a in assets { context.insert(a) }
 try context.save()
 } catch {
 print("HubNode: asset seed failed (hubs still available): \(error)")
 }
 }

 @MainActor
 private static func clearAll(context: ModelContext) throws {
 try deleteAll(ObservationRecord.self, context: context)
 try deleteAll(SessionTask.self, context: context)
 try deleteAll(Assignment.self, context: context)
 try deleteAll(HubSession.self, context: context)
 try deleteAll(SituationRecord.self, context: context)
 try deleteAll(HubAsset.self, context: context)
 try deleteAll(Hub.self, context: context)
 try deleteAll(RoleDef.self, context: context)
 try deleteAll(TaskTemplate.self, context: context)
 try deleteAll(GuideChunk.self, context: context)
 try deleteAll(FeedSourceState.self, context: context)
 try context.save()
 }

 private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
 for item in try context.fetch(FetchDescriptor<T>()) {
 context.delete(item)
 }
 }

 // MARK: - Resource resolution

 static func resourceURL(_ name: String, ext: String) throws -> URL {
 // 1) Bundle root (how Xcode Copy Bundle Resources places them)
 if let url = Bundle.main.url(forResource: name, withExtension: ext) {
 return url
 }
 // 2) Bundle Corpus/ subdirectory
 if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Corpus") {
 return url
 }
 if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Corpus") {
 return url
 }
 // 3) Enumerate bundle resources (debug-friendly)
 if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
 if let match = urls.first(where: { $0.deletingPathExtension().lastPathComponent == name }) {
 return match
 }
 }
 // 4) Source-tree fallbacks when running from Xcode
 let file = URL(fileURLWithPath: #filePath)
 let candidates = [
 file.deletingLastPathComponent().deletingLastPathComponent()
 .appendingPathComponent("Resources/Corpus/\(name).\(ext)"),
 URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
 .appendingPathComponent("HubNode/HubNode/Resources/Corpus/\(name).\(ext)"),
 URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
 .appendingPathComponent("HubNode/Resources/Corpus/\(name).\(ext)"),
 URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
 .appendingPathComponent("out/\(name).\(ext)"),
 ]
 for c in candidates where FileManager.default.fileExists(atPath: c.path) {
 return c
 }
 throw CorpusBootstrapError.missingResource("\(name).\(ext). Bundle: \(Bundle.main.bundlePath)")
 }

 private static func loadNeighbours() throws -> [String: [String]] {
 let url = try resourceURL("neighbours", ext: "json")
 return try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url))
 }

 private static func loadAssets(hubByID: [String: Hub]) throws -> [HubAsset] {
 let url = try resourceURL("assets", ext: "csv")
 let text = try String(contentsOf: url, encoding: .utf8)
 // Line-oriented quote-aware parse (same as hubs CSV fix)
 var header: [String] = []
 let byName = Dictionary(uniqueKeysWithValues: hubByID.values.map { ($0.name, $0) })
 var out: [HubAsset] = []
 for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
 let cols = parseCSVLine(String(line))
 if index == 0 {
 header = cols.map { $0.trimmingCharacters(in: .whitespaces) }
 continue
 }
 guard cols.count >= 4 else { continue }
 var row: [String: String] = [:]
 for (i, h) in header.enumerated() where i < cols.count {
 row[h] = cols[i]
 }
 let hubName = row["hub"] ?? cols[safe: 0]
 let assetName = nonempty(row["asset"] ?? cols[safe: 3])
 guard let hubName, let assetName, let hub = byName[hubName] else { continue }
 let sensitivity = AssetSensitivity(rawValue: row["sensitivity"] ?? cols[safe: 4] ?? "restricted") ?? .restricted
 let kind = row["kind"] ?? cols[safe: 2] ?? "place"
 let asset = HubAsset(kind: kind, name: assetName, sensitivity: sensitivity, hub: hub)
 hub.assets.append(asset)
 out.append(asset)
 }
 return out
 }

 private static func loadRoles() throws -> [RoleDef] {
 let url = try resourceURL("roles", ext: "csv")
 return try CSV.parse(String(contentsOf: url, encoding: .utf8)).compactMap { row in
 guard let code = nonempty(row["code"]), let name = nonempty(row["name"]) else { return nil }
 return RoleDef(
 code: code,
 name: name,
 roleDescription: row["description"] ?? "",
 priorityRank: Int(row["priority_rank"] ?? "") ?? 99,
 sourceRef: row["source_ref"] ?? "WREMO Hub Guide"
 )
 }
 }

 private static func loadTaskTemplates() throws -> [TaskTemplate] {
 let url = try resourceURL("task_templates", ext: "csv")
 let text = try String(contentsOf: url, encoding: .utf8)
 var header: [String] = []
 var out: [TaskTemplate] = []
 for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
 let cols = parseCSVLine(String(line))
 if index == 0 {
 header = cols.map { $0.trimmingCharacters(in: .whitespaces) }
 continue
 }
 var row: [String: String] = [:]
 for (i, h) in header.enumerated() where i < cols.count {
 row[h] = cols[i]
 }
 guard let body = nonempty(row["text"] ?? cols[safe: 3]) else { continue }
 let id = nonempty(row["id"] ?? cols[safe: 0]) ?? "tt-\(body.prefix(24).hashValue)"
 let phaseRaw = row["phase"] ?? cols[safe: 2] ?? "response"
 let phase = TaskPhase(rawValue: phaseRaw) ?? .response
 out.append(TaskTemplate(
 id: id,
 roleCode: row["role_code"] ?? cols[safe: 1] ?? "hub_supervisor",
 phase: phase,
 text: body,
 sourceRef: row["source_ref"] ?? cols[safe: 4] ?? "WREMO Hub Guide"
 ))
 }
 return out
 }

 private static func loadGuideChunks() throws -> [GuideChunk] {
 let url = try resourceURL("guide_chunks", ext: "jsonl")
 let text = try String(contentsOf: url, encoding: .utf8)
 var out: [GuideChunk] = []
 for line in text.split(separator: "\n") where !line.isEmpty {
 guard let data = line.data(using: .utf8),
 let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
 out.append(GuideChunk(
 section: obj["section"] as? String ?? "",
 part: obj["part"] as? Int ?? 0,
 text: obj["text"] as? String ?? "",
 sourceRef: obj["source_ref"] as? String ?? "WREMO Hub Guide"
 ))
 }
 return out
 }

 private static func nonempty(_ s: String?) -> String? {
 guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
 return s
 }
}

/// Codable wire format for hubs.json
private struct HubMapItemDTO: Codable {
 var id: String
 var name: String
 var taName: String
 var address: String
 var latitude: Double
 var longitude: Double
 var crpURL: String?
 var crpReviewedOn: String?
 var neighbourIDs: [String]
 var nAssetsPublic: Int
 var nAssetsRestricted: Int

 func asMapItem() -> HubMapItem {
 HubMapItem(
 id: id,
 name: name,
 taName: taName,
 address: address,
 latitude: latitude,
 longitude: longitude,
 crpURL: crpURL,
 crpReviewedOn: crpReviewedOn,
 neighbourIDs: neighbourIDs,
 nAssetsPublic: nAssetsPublic,
 nAssetsRestricted: nAssetsRestricted
 )
 }
}

private extension Array {
 subscript(safe index: Int) -> Element? {
 indices.contains(index) ? self[index] : nil
 }
}

// MARK: - CSV

enum CSV {
 static func parse(_ text: String) throws -> [[String: String]] {
 var rows: [[String: String]] = []
 let lines = splitLines(text)
 guard let headerLine = lines.first else { return [] }
 let headers = parseRow(headerLine).map { $0.trimmingCharacters(in: .whitespaces) }
 for line in lines.dropFirst() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
 let cols = parseRow(line)
 var dict: [String: String] = [:]
 for (i, h) in headers.enumerated() {
 dict[h] = i < cols.count ? cols[i] : ""
 }
 rows.append(dict)
 }
 return rows
 }

 private static func splitLines(_ text: String) -> [String] {
 var lines: [String] = []
 var current = ""
 var inQuotes = false
 for ch in text {
 if ch == "\"" {
 inQuotes.toggle()
 current.append(ch)
 } else if (ch == "\n" || ch == "\r") && !inQuotes {
 if !current.isEmpty { lines.append(current) }
 current = ""
 } else {
 current.append(ch)
 }
 }
 if !current.isEmpty { lines.append(current) }
 return lines
 }

 private static func parseRow(_ line: String) -> [String] {
 var cols: [String] = []
 var current = ""
 var inQuotes = false
 var i = line.startIndex
 while i < line.endIndex {
 let ch = line[i]
 if ch == "\"" {
 let next = line.index(after: i)
 if inQuotes && next < line.endIndex && line[next] == "\"" {
 current.append("\"")
 i = line.index(after: next)
 continue
 }
 inQuotes.toggle()
 i = line.index(after: i)
 continue
 }
 if ch == "," && !inQuotes {
 cols.append(current)
 current = ""
 i = line.index(after: i)
 continue
 }
 current.append(ch)
 i = line.index(after: i)
 }
 cols.append(current)
 return cols
 }
}
