import Foundation
import SwiftData

/// Upserts CAP observations; handles Cancel/supersede (architecture.md §5, §7).
@MainActor
final class ObservationStore {
 private let context: ModelContext

 init(context: ModelContext) {
 self.context = context
 }

 @discardableResult
 func upsert(_ alert: CAPAlert) throws -> ObservationRecord {
 let id = alert.id
 let descriptor = FetchDescriptor<ObservationRecord>(
 predicate: #Predicate { $0.id == id }
 )
 if let existing = try context.fetch(descriptor).first {
 if alert.msgType == .cancel {
 existing.apply(alert)
 existing.isActive = false
 // Mark any referenced actives superseded
 for ref in alert.references {
 try markSuperseded(externalOrFullID: ref, by: id)
 }
 } else {
 existing.apply(alert)
 }
 try context.save()
 return existing
 }

 let record = ObservationRecord(from: alert)
 if alert.msgType == .cancel {
 record.isActive = false
 for ref in alert.references {
 try markSuperseded(externalOrFullID: ref, by: id)
 }
 }
 context.insert(record)
 try context.save()
 return record
 }

 func activeAlerts(at cursor: Date) throws -> [CAPAlert] {
 let descriptor = FetchDescriptor<ObservationRecord>(
 predicate: #Predicate { $0.isActive == true }
 )
 let records = try context.fetch(descriptor)
 return records
 .filter { $0.observedAt <= cursor }
 .filter { rec in
 if let exp = rec.expiresAt { return exp >= cursor }
 return true
 }
 .map { $0.asCAPAlert() }
 }

 func allSourceCadences() throws -> [String: TimeInterval] {
 let sources = try context.fetch(FetchDescriptor<FeedSourceState>())
 if sources.isEmpty {
 return Dictionary(uniqueKeysWithValues: FixtureCatalog.sources.map { ($0.id, $0.cadence) })
 }
 return Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.cadence) })
 }

 private func markSuperseded(externalOrFullID: String, by newID: String) throws {
 let all = try context.fetch(FetchDescriptor<ObservationRecord>())
 for rec in all where rec.id == externalOrFullID || rec.externalID == externalOrFullID || rec.id.hasSuffix("::\(externalOrFullID)") {
 rec.supersededByID = newID
 rec.isActive = false
 }
 }
}
