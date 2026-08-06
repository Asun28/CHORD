import Foundation
import SwiftData
import CoreLocation

// MARK: - Enums shared with UI

public enum AssetSensitivity: String, Codable, Sendable {
    case `public`
    case restricted
}

public enum TaskPhase: String, Codable, Sendable, CaseIterable {
    case access
    case team
    case setup
    case before_open
    case response
    case recovery

    public var title: String {
        switch self {
        case .access: "Accessing the hub"
        case .team: "Working as a team"
        case .setup: "Setting up"
        case .before_open: "Before you open"
        case .response: "Community response"
        case .recovery: "Recovery"
        }
    }
}

// MARK: - SwiftData models

@Model
public final class Hub {
    @Attribute(.unique) public var id: String
    public var name: String
    public var taName: String
    public var address: String
    public var latitude: Double
    public var longitude: Double
    public var crpURL: String?
    public var crpReviewedOn: String?
    public var kitContentsJSON: String
    public var neighbourIDs: [String]
    public var nAssetsPublic: Int
    public var nAssetsRestricted: Int

    @Relationship(deleteRule: .cascade, inverse: \HubAsset.hub)
    public var assets: [HubAsset]

    @Relationship(deleteRule: .cascade, inverse: \SituationRecord.hub)
    public var situations: [SituationRecord]

    @Relationship(deleteRule: .cascade, inverse: \HubSession.hub)
    public var sessions: [HubSession]

    public init(
        id: String,
        name: String,
        taName: String,
        address: String,
        latitude: Double,
        longitude: Double,
        crpURL: String? = nil,
        crpReviewedOn: String? = nil,
        kitContentsJSON: String = "[]",
        neighbourIDs: [String] = [],
        nAssetsPublic: Int = 0,
        nAssetsRestricted: Int = 0
    ) {
        self.id = id
        self.name = name
        self.taName = taName
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.crpURL = crpURL
        self.crpReviewedOn = crpReviewedOn
        self.kitContentsJSON = kitContentsJSON
        self.neighbourIDs = neighbourIDs
        self.nAssetsPublic = nAssetsPublic
        self.nAssetsRestricted = nAssetsRestricted
        self.assets = []
        self.situations = []
        self.sessions = []
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var planCurrency: PlanCurrency {
        PlanCurrency.from(reviewedOn: crpReviewedOn)
    }
}

public enum PlanCurrency: String, Sendable {
    case current      // ≤24 months
    case ageing       // 24–48
    case stale        // >48
    case missing

    public static func from(reviewedOn: String?, asOf: Date = .now) -> PlanCurrency {
        guard let reviewedOn, !reviewedOn.isEmpty else { return .missing }
        // Accept yyyy-MM or yyyy-MM-dd
        let parts = reviewedOn.split(separator: "-").map(String.init)
        guard let y = parts.first.flatMap(Int.init) else { return .missing }
        let m = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
        var comp = DateComponents()
        comp.year = y
        comp.month = m
        comp.day = 1
        guard let date = Calendar.current.date(from: comp) else { return .missing }
        let months = Calendar.current.dateComponents([.month], from: date, to: asOf).month ?? 0
        if months <= 24 { return .current }
        if months <= 48 { return .ageing }
        return .stale
    }
}

@Model
public final class HubAsset {
    public var kind: String
    public var name: String
    public var sensitivityRaw: String
    public var hub: Hub?

    public init(kind: String, name: String, sensitivity: AssetSensitivity, hub: Hub? = nil) {
        self.kind = kind
        self.name = name
        self.sensitivityRaw = sensitivity.rawValue
        self.hub = hub
    }

    public var sensitivity: AssetSensitivity {
        AssetSensitivity(rawValue: sensitivityRaw) ?? .restricted
    }
}

@Model
public final class RoleDef {
    @Attribute(.unique) public var code: String
    public var name: String
    public var roleDescription: String
    public var priorityRank: Int
    public var sourceRef: String

    public init(code: String, name: String, roleDescription: String, priorityRank: Int, sourceRef: String) {
        self.code = code
        self.name = name
        self.roleDescription = roleDescription
        self.priorityRank = priorityRank
        self.sourceRef = sourceRef
    }

    public var isPriority: Bool { priorityRank >= 1 && priorityRank <= 4 }
}

@Model
public final class TaskTemplate {
    @Attribute(.unique) public var id: String
    public var roleCode: String
    public var phaseRaw: String
    public var text: String
    public var sourceRef: String

    public init(id: String, roleCode: String, phase: TaskPhase, text: String, sourceRef: String) {
        self.id = id
        self.roleCode = roleCode
        self.phaseRaw = phase.rawValue
        self.text = text
        self.sourceRef = sourceRef
    }

    public var phase: TaskPhase {
        TaskPhase(rawValue: phaseRaw) ?? .response
    }
}

@Model
public final class GuideChunk {
    public var section: String
    public var part: Int
    public var text: String
    public var sourceRef: String

    public init(section: String, part: Int, text: String, sourceRef: String) {
        self.section = section
        self.part = part
        self.text = text
        self.sourceRef = sourceRef
    }
}

@Model
public final class ObservationRecord {
    @Attribute(.unique) public var id: String  // sourceID::externalID
    public var sourceID: String
    public var externalID: String
    public var msgTypeRaw: String
    public var observedAt: Date
    public var fetchedAt: Date
    public var expiresAt: Date?
    public var headline: String
    public var detail: String
    public var severityRaw: String
    public var urgencyRaw: String
    public var certaintyRaw: String
    public var hazardClassRaw: String
    public var quality: String?
    public var trustTierRaw: Int
    public var attribution: String
    public var latitude: Double?
    public var longitude: Double?
    public var radiusMeters: Double?
    public var areaPolygonJSON: String?
    public var capJSON: String?
    public var supersededByID: String?
    public var isActive: Bool

    public init(from alert: CAPAlert) {
        self.id = alert.id
        self.sourceID = alert.sourceID
        self.externalID = alert.externalID
        self.msgTypeRaw = alert.msgType.rawValue
        self.observedAt = alert.observedAt
        self.fetchedAt = alert.fetchedAt
        self.expiresAt = alert.expiresAt
        self.headline = alert.headline
        self.detail = alert.description
        self.severityRaw = alert.severity.rawValue
        self.urgencyRaw = alert.urgency.rawValue
        self.certaintyRaw = alert.certainty.rawValue
        self.hazardClassRaw = alert.hazardClass.rawValue
        self.quality = alert.quality
        self.trustTierRaw = alert.trustTier.rawValue
        self.attribution = alert.attribution
        self.latitude = alert.latitude
        self.longitude = alert.longitude
        self.radiusMeters = alert.radiusMeters
        if let poly = alert.areaPolygon,
           let data = try? JSONEncoder().encode(poly),
           let s = String(data: data, encoding: .utf8) {
            self.areaPolygonJSON = s
        } else {
            self.areaPolygonJSON = nil
        }
        self.capJSON = alert.rawJSON
        self.supersededByID = nil
        self.isActive = alert.msgType != .cancel
    }

    public func apply(_ alert: CAPAlert) {
        msgTypeRaw = alert.msgType.rawValue
        observedAt = alert.observedAt
        fetchedAt = alert.fetchedAt
        expiresAt = alert.expiresAt
        headline = alert.headline
        detail = alert.description
        severityRaw = alert.severity.rawValue
        urgencyRaw = alert.urgency.rawValue
        certaintyRaw = alert.certainty.rawValue
        hazardClassRaw = alert.hazardClass.rawValue
        quality = alert.quality
        trustTierRaw = alert.trustTier.rawValue
        attribution = alert.attribution
        latitude = alert.latitude
        longitude = alert.longitude
        radiusMeters = alert.radiusMeters
        capJSON = alert.rawJSON
        if alert.msgType == .cancel {
            isActive = false
        } else {
            isActive = true
        }
    }

    public func asCAPAlert() -> CAPAlert {
        var poly: [[Double]]? = nil
        if let areaPolygonJSON,
           let data = areaPolygonJSON.data(using: .utf8) {
            poly = try? JSONDecoder().decode([[Double]].self, from: data)
        }
        return CAPAlert(
            sourceID: sourceID,
            externalID: externalID,
            msgType: CAPAlert.MsgType(rawValue: msgTypeRaw) ?? .alert,
            observedAt: observedAt,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            headline: headline,
            description: detail,
            severity: CAPAlert.Severity(rawValue: severityRaw) ?? .unknown,
            urgency: CAPAlert.Urgency(rawValue: urgencyRaw) ?? .unknown,
            certainty: CAPAlert.Certainty(rawValue: certaintyRaw) ?? .unknown,
            hazardClass: CAPAlert.HazardClass(rawValue: hazardClassRaw) ?? .other,
            quality: quality,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            areaPolygon: poly,
            trustTier: TrustTier(rawValue: trustTierRaw) ?? .p3,
            attribution: attribution,
            rawJSON: capJSON
        )
    }
}

@Model
public final class SituationRecord {
    public var computedAt: Date
    public var postureRaw: String
    public var driversJSON: String
    public var hub: Hub?

    public init(computedAt: Date, posture: Posture, driversJSON: String, hub: Hub? = nil) {
        self.computedAt = computedAt
        self.postureRaw = posture.rawValue
        self.driversJSON = driversJSON
        self.hub = hub
    }

    public var posture: Posture {
        Posture(rawValue: postureRaw) ?? .green
    }
}

@Model
public final class HubSession {
    @Attribute(.unique) public var id: String
    public var openedAt: Date
    public var openedBy: String
    public var hub: Hub?

    @Relationship(deleteRule: .cascade, inverse: \Assignment.session)
    public var assignments: [Assignment]

    @Relationship(deleteRule: .cascade, inverse: \SessionTask.session)
    public var tasks: [SessionTask]

    public init(id: String = UUID().uuidString, openedAt: Date = .now, openedBy: String, hub: Hub? = nil) {
        self.id = id
        self.openedAt = openedAt
        self.openedBy = openedBy
        self.hub = hub
        self.assignments = []
        self.tasks = []
    }
}

@Model
public final class Assignment {
    /// Display name: "First Last" — for lists and HTML export.
    public var personName: String
    /// Prefer these for web roster; empty if migrated from older sessions.
    public var firstName: String = ""
    public var lastName: String = ""
    public var roleCode: String
    public var assignedAt: Date
    public var rationale: String
    public var session: HubSession?

    public init(
        firstName: String,
        lastName: String,
        roleCode: String,
        assignedAt: Date = .now,
        rationale: String,
        session: HubSession? = nil
    ) {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.firstName = first
        self.lastName = last
        self.personName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        self.roleCode = roleCode
        self.assignedAt = assignedAt
        self.rationale = rationale
        self.session = session
    }

    public var resolvedFirstName: String {
        if !firstName.isEmpty { return firstName }
        return personName.split(separator: " ").first.map(String.init) ?? personName
    }

    public var resolvedLastName: String {
        if !lastName.isEmpty { return lastName }
        let parts = personName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        return parts.count > 1 ? String(parts[1]) : ""
    }
}

@Model
public final class SessionTask {
    public var templateID: String
    public var roleCode: String
    public var text: String
    public var sourceRef: String
    public var statusRaw: String
    public var reason: String
    public var createdAt: Date
    public var assigneeName: String?
    public var session: HubSession?

    public init(
        templateID: String,
        roleCode: String,
        text: String,
        sourceRef: String,
        status: String = "open",
        reason: String,
        createdAt: Date = .now,
        assigneeName: String? = nil,
        session: HubSession? = nil
    ) {
        self.templateID = templateID
        self.roleCode = roleCode
        self.text = text
        self.sourceRef = sourceRef
        self.statusRaw = status
        self.reason = reason
        self.createdAt = createdAt
        self.assigneeName = assigneeName
        self.session = session
    }
}

@Model
public final class FeedSourceState {
    @Attribute(.unique) public var id: String
    public var name: String
    public var trustTierRaw: Int
    public var cadence: TimeInterval
    public var attribution: String
    public var lastFetchedAt: Date?
    public var lastSuccessAt: Date?
    public var isPaused: Bool
    public var lastError: String?

    public init(from meta: SourceMetadata) {
        self.id = meta.id
        self.name = meta.name
        self.trustTierRaw = meta.trustTier.rawValue
        self.cadence = meta.cadence
        self.attribution = meta.attribution
        self.lastFetchedAt = nil
        self.lastSuccessAt = nil
        self.isPaused = false
        self.lastError = nil
    }

    public var trustTier: TrustTier {
        TrustTier(rawValue: trustTierRaw) ?? .p3
    }
}
