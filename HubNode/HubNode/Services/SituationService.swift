import Foundation
import SwiftData

@MainActor
final class SituationService {
    private let context: ModelContext
    private let observations: ObservationStore

    init(context: ModelContext) {
        self.context = context
        self.observations = ObservationStore(context: context)
    }

    func recompute(hub: Hub, at cursor: Date) throws -> SituationSnapshot {
        let alerts = try observations.activeAlerts(at: cursor)
        let cadences = try observations.allSourceCadences()
        let snap = PostureEngine.recompute(
            hubID: hub.id,
            hubLatitude: hub.latitude,
            hubLongitude: hub.longitude,
            alerts: alerts,
            sourceCadences: cadences,
            at: cursor
        )
        // Persist latest
        let driversData = try JSONEncoder().encode(snap.drivers)
        let driversJSON = String(data: driversData, encoding: .utf8) ?? "[]"
        if let existing = hub.situations.sorted(by: { $0.computedAt > $1.computedAt }).first {
            existing.computedAt = snap.computedAt
            existing.postureRaw = snap.posture.rawValue
            existing.driversJSON = driversJSON
        } else {
            let rec = SituationRecord(
                computedAt: snap.computedAt,
                posture: snap.posture,
                driversJSON: driversJSON,
                hub: hub
            )
            hub.situations.append(rec)
            context.insert(rec)
        }
        try context.save()
        return snap
    }

    func recomputeAll(at cursor: Date) throws -> [String: SituationSnapshot] {
        let hubs = try context.fetch(FetchDescriptor<Hub>())
        var out: [String: SituationSnapshot] = [:]
        for hub in hubs {
            out[hub.id] = try recompute(hub: hub, at: cursor)
        }
        return out
    }

    func cachedPosture(hub: Hub) -> Posture {
        hub.situations.sorted { $0.computedAt > $1.computedAt }.first?.posture ?? .green
    }
}
