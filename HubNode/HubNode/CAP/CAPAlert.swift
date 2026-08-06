import Foundation
import CoreLocation

/// Normalised CAP-aligned alert (architecture.md ADR-001).
/// Adapters produce raw items; the normaliser produces this.
public struct CAPAlert: Codable, Sendable, Identifiable, Hashable {
 public var id: String { "\(sourceID)::\(externalID)" }

 public var sourceID: String
 public var externalID: String
 public var msgType: MsgType
 public var observedAt: Date
 public var fetchedAt: Date
 public var expiresAt: Date?

 public var headline: String
 public var description: String
 public var instruction: String?

 public var severity: Severity
 public var urgency: Urgency
 public var certainty: Certainty

 public var hazardClass: HazardClass
 public var quality: String? // e.g. GeoNet quality; "deleted" excluded by rules
 public var references: [String] // CAP references for Update/Cancel

 public var latitude: Double?
 public var longitude: Double?
 public var radiusMeters: Double?
 public var areaPolygon: [[Double]]? // [[lon, lat], ...] rings simplified

 public var trustTier: TrustTier
 public var attribution: String
 public var rawJSON: String?

 public enum MsgType: String, Codable, Sendable {
 case alert, update, cancel
 }

 public enum Severity: String, Codable, Sendable, Comparable {
 case unknown, minor, moderate, severe, extreme

 private var rank: Int {
 switch self {
 case .unknown: 0
 case .minor: 1
 case .moderate: 2
 case .severe: 3
 case .extreme: 4
 }
 }

 public static func < (lhs: Severity, rhs: Severity) -> Bool {
 lhs.rank < rhs.rank
 }
 }

 public enum Urgency: String, Codable, Sendable {
 case unknown, past, future, expected, immediate
 }

 public enum Certainty: String, Codable, Sendable {
 case unknown, unlikely, possible, likely, observed
 }

 public enum HazardClass: String, Codable, Sendable {
 case quake
 case weather
 case road
 case river
 case other
 }

 public var coordinate: CLLocationCoordinate2D? {
 guard let latitude, let longitude else { return nil }
 return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
 }

 public init(
 sourceID: String,
 externalID: String,
 msgType: MsgType = .alert,
 observedAt: Date,
 fetchedAt: Date = .now,
 expiresAt: Date? = nil,
 headline: String,
 description: String = "",
 instruction: String? = nil,
 severity: Severity = .unknown,
 urgency: Urgency = .unknown,
 certainty: Certainty = .unknown,
 hazardClass: HazardClass = .other,
 quality: String? = nil,
 references: [String] = [],
 latitude: Double? = nil,
 longitude: Double? = nil,
 radiusMeters: Double? = nil,
 areaPolygon: [[Double]]? = nil,
 trustTier: TrustTier,
 attribution: String,
 rawJSON: String? = nil
 ) {
 self.sourceID = sourceID
 self.externalID = externalID
 self.msgType = msgType
 self.observedAt = observedAt
 self.fetchedAt = fetchedAt
 self.expiresAt = expiresAt
 self.headline = headline
 self.description = description
 self.instruction = instruction
 self.severity = severity
 self.urgency = urgency
 self.certainty = certainty
 self.hazardClass = hazardClass
 self.quality = quality
 self.references = references
 self.latitude = latitude
 self.longitude = longitude
 self.radiusMeters = radiusMeters
 self.areaPolygon = areaPolygon
 self.trustTier = trustTier
 self.attribution = attribution
 self.rawJSON = rawJSON
 }
}
