import Foundation

// MARK: - Flow: deterministic posture
/// Rules-only green/watch/act/respond. Trust tiers, spatial match, staleness.
/// Models must never call this path (architecture.md §2, §5).

public struct SituationDriver: Codable, Sendable, Hashable, Identifiable {
 public var id: String
 public var observationID: String
 public var sourceID: String
 public var headline: String
 public var observedAt: Date
 public var trustTier: TrustTier
 public var severity: CAPAlert.Severity
 public var hazardClass: CAPAlert.HazardClass
 public var attribution: String
 public var isStale: Bool
 public var ageSeconds: TimeInterval

 public var ageLabel: String {
 AgeFormatting.label(ageSeconds: ageSeconds)
 }
}

public struct SituationSnapshot: Sendable, Hashable {
 public var hubID: String
 public var computedAt: Date
 public var cursor: Date
 public var posture: Posture
 public var drivers: [SituationDriver]
 public var annotations: [SituationDriver] // P3 / non-raising
 public var degradedSources: [String]
}

public enum PostureEngine {
 /// Cadence multiplier before a tile is considered stale (architecture.md §5).
 public static let staleCadenceMultiplier: Double = 3

 public static let p2CorroborationWindow: TimeInterval = 60 * 60

 public static func recompute(
 hubID: String,
 hubLatitude: Double,
 hubLongitude: Double,
 alerts: [CAPAlert],
 sourceCadences: [String: TimeInterval],
 at cursor: Date = .now
 ) -> SituationSnapshot {
 var raising: [SituationDriver] = []
 var annotations: [SituationDriver] = []
 var degraded: Set<String> = []

 let active = alerts.filter { alert in
 // Time cursor: only observations at or before cursor
 guard alert.observedAt <= cursor else { return false }
 // Exclude deleted quality
 if let q = alert.quality?.lowercased(), q == "deleted" { return false }
 // Cancel messages are handled by store (supersede); ignore pure cancels here
 if alert.msgType == .cancel { return false }
 if let exp = alert.expiresAt, exp < cursor { return false }
 return SpatialMatch.affectsHub(
 alert: alert,
 hubLatitude: hubLatitude,
 hubLongitude: hubLongitude
 )
 }

 for alert in active {
 let age = cursor.timeIntervalSince(alert.observedAt)
 let cadence = sourceCadences[alert.sourceID] ?? 3600
 let stale = age > cadence * staleCadenceMultiplier
 if stale { degraded.insert(alert.sourceID) }

 let driver = SituationDriver(
 id: alert.id,
 observationID: alert.id,
 sourceID: alert.sourceID,
 headline: alert.headline,
 observedAt: alert.observedAt,
 trustTier: alert.trustTier,
 severity: alert.severity,
 hazardClass: alert.hazardClass,
 attribution: alert.attribution,
 isStale: stale,
 ageSeconds: max(0, age)
 )

 if alert.trustTier.annotatesOnly {
 annotations.append(driver)
 } else {
 raising.append(driver)
 }
 }

 let posture = computePosture(drivers: raising, at: cursor)
 return SituationSnapshot(
 hubID: hubID,
 computedAt: .now,
 cursor: cursor,
 posture: posture,
 drivers: raising.sorted { $0.observedAt > $1.observedAt },
 annotations: annotations.sorted { $0.observedAt > $1.observedAt },
 degradedSources: degraded.sorted()
 )
 }

 static func computePosture(drivers: [SituationDriver], at cursor: Date) -> Posture {
 guard !drivers.isEmpty else { return .green }

 let p0p1 = drivers.filter { $0.trustTier.mayRaisePostureAlone }
 let p2 = drivers.filter { $0.trustTier == .p2 }

 // respond: severe/extreme + immediate-style high severity on P0/P1
 if p0p1.contains(where: { $0.severity >= .severe && ($0.hazardClass == .quake || $0.hazardClass == .weather || $0.hazardClass == .river) }) {
 return .respond
 }

 // act: any P0/P1 warning-level (moderate+)
 if p0p1.contains(where: { $0.severity >= .moderate }) {
 return .act
 }

 // watch: P0/P1 advisory (minor/unknown) or corroborated P2
 if !p0p1.isEmpty {
 return .watch
 }

 if isCorroborated(p2: p2, at: cursor) {
 return .watch
 }

 // Lone P2 without corroboration does not raise posture
 return .green
 }

 static func isCorroborated(p2: [SituationDriver], at cursor: Date) -> Bool {
 guard p2.count >= 2 else { return false }
 // ≥2 independent sources within window
 let recent = p2.filter { cursor.timeIntervalSince($0.observedAt) <= p2CorroborationWindow }
 let sources = Set(recent.map(\.sourceID))
 return sources.count >= 2
 }
}

public enum AgeFormatting {
 public static func label(ageSeconds: TimeInterval) -> String {
 let s = Int(ageSeconds)
 if s < 60 { return "\(s)s ago" }
 if s < 3600 { return "\(s / 60) min ago" }
 if s < 86_400 {
 let h = s / 3600
 let m = (s % 3600) / 60
 return m == 0 ? "\(h)h ago" : "\(h)h \(m)m ago"
 }
 let d = s / 86_400
 return d == 1 ? "1 day ago" : "\(d) days ago"
 }
}
