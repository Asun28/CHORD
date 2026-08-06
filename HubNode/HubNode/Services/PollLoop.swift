import Foundation
import SwiftData

// MARK: - Flow: ingest poll
/// Single scheduled loop: adapters → CAP normalise → observation upsert.
/// No message bus (architecture.md §4). Posture is recomputed separately.
@MainActor
final class PollLoop {
 private let context: ModelContext
 private let store: ObservationStore
 private var adapters: [any FeedAdapter]
 private var pausedSources: Set<String> = []

 init(context: ModelContext, adapters: [any FeedAdapter] = DemoReplay.adapters()) {
 self.context = context
 self.store = ObservationStore(context: context)
 self.adapters = adapters
 }

 func setAdapters(_ adapters: [any FeedAdapter]) {
 self.adapters = adapters
 }

 func setPaused(_ sourceID: String, paused: Bool) {
 if paused { pausedSources.insert(sourceID) }
 else { pausedSources.remove(sourceID) }
 }

 var paused: Set<String> { pausedSources }

 @discardableResult
 func poll(at cursor: Date) async throws -> Int {
 // Ensure source state rows exist
 try ensureSources()

 var count = 0
 for adapter in adapters {
 if pausedSources.contains(adapter.sourceID) {
 try markPaused(adapter.sourceID)
 continue
 }
 do {
 let items = try await adapter.fetch(at: cursor)
 for item in items {
 let alert = try CAPNormaliser.normalise(
 item: item,
 source: adapter.source,
 fetchedAt: .now
 )
 try store.upsert(alert)
 count += 1
 }
 try markSuccess(adapter.source)
 } catch {
 try markError(adapter.sourceID, message: error.localizedDescription)
 }
 }
 return count
 }

 private func ensureSources() throws {
 let existing = try context.fetch(FetchDescriptor<FeedSourceState>())
 let have = Set(existing.map(\.id))
 for meta in FixtureCatalog.sources where !have.contains(meta.id) {
 context.insert(FeedSourceState(from: meta))
 }
 try context.save()
 }

 private func markSuccess(_ meta: SourceMetadata) throws {
 let id = meta.id
 let d = FetchDescriptor<FeedSourceState>(predicate: #Predicate { $0.id == id })
 if let s = try context.fetch(d).first {
 s.lastFetchedAt = .now
 s.lastSuccessAt = .now
 s.lastError = nil
 s.isPaused = false
 }
 try context.save()
 }

 private func markError(_ id: String, message: String) throws {
 let d = FetchDescriptor<FeedSourceState>(predicate: #Predicate { $0.id == id })
 if let s = try context.fetch(d).first {
 s.lastFetchedAt = .now
 s.lastError = message
 }
 try context.save()
 }

 private func markPaused(_ id: String) throws {
 let d = FetchDescriptor<FeedSourceState>(predicate: #Predicate { $0.id == id })
 if let s = try context.fetch(d).first {
 s.isPaused = true
 }
 try context.save()
 }
}
