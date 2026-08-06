import Foundation

// MARK: - View level

/// Which tier of the board is asking. The privacy gate is enforced against this
/// value inside `HubFactStore` — at the query, never in a prompt (architecture.md §8).
public enum ViewLevel: String, Codable, Sendable, CaseIterable {
    case `public`
    case coordinator

    public var title: String {
        switch self {
        case .public: "Board view"
        case .coordinator: "Coordinator view"
        }
    }

    public var subtitle: String {
        switch self {
        case .public: "public assets only"
        case .coordinator: "restricted locations included"
        }
    }
}

// MARK: - Provenance

/// One traceable source behind a claim. Built by the app from the rows and
/// passages actually used — never taken on trust from a model (ADR-006).
public struct CitationVO: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case guideSection
        case hubPlan
        case taskCatalogue
        case roleCatalogue
        case hubRecord
        case observation

        public var label: String {
            switch self {
            case .guideSection: "Hub Guide"
            case .hubPlan: "Community Response Plan"
            case .taskCatalogue: "Task catalogue"
            case .roleCatalogue: "Role catalogue"
            case .hubRecord: "Hub record"
            case .observation: "Observation"
            }
        }
    }

    public var kind: Kind
    public var sourceRef: String
    public var detail: String
    public var reviewedOn: String?

    public init(kind: Kind, sourceRef: String, detail: String = "", reviewedOn: String? = nil) {
        self.kind = kind
        self.sourceRef = sourceRef
        self.detail = detail
        self.reviewedOn = reviewedOn
    }

    public var id: String { "\(kind.rawValue)|\(sourceRef)|\(detail)" }

    /// Provenance plus age on the same line — a 2019 plan should say so (§7).
    public var label: String {
        var out = sourceRef
        if let d = detail.nonEmptyTrimmed { out += " — \(d)" }
        if let r = reviewedOn.nonEmptyTrimmed { out += " · reviewed \(r)" }
        return out
    }
}

// MARK: - Retrieved prose

/// A prose passage that survived the privacy gate and scored against the question.
public struct RetrievedPassageVO: Sendable, Hashable, Identifiable {
    public enum Origin: String, Sendable {
        case guide
        case hubPlan
    }

    public var id: String
    public var origin: Origin
    /// `nil` for the regional Hub Guide; a hub slug for plan prose. Retrieval
    /// only ever loads plan passages whose `hubID` is the current hub.
    public var hubID: String?
    public var section: String
    public var text: String
    public var sourceRef: String
    public var reviewedOn: String?
    public var score: Double

    public init(
        id: String,
        origin: Origin,
        hubID: String? = nil,
        section: String,
        text: String,
        sourceRef: String,
        reviewedOn: String? = nil,
        score: Double = 0
    ) {
        self.id = id
        self.origin = origin
        self.hubID = hubID
        self.section = section
        self.text = text
        self.sourceRef = sourceRef
        self.reviewedOn = reviewedOn
        self.score = score
    }

    public var citation: CitationVO {
        CitationVO(
            kind: origin == .guide ? .guideSection : .hubPlan,
            sourceRef: sourceRef,
            detail: section,
            reviewedOn: reviewedOn
        )
    }
}

// MARK: - Structured facts

public struct HubAssetVO: Sendable, Hashable, Identifiable {
    public var id: String { "\(kind)|\(name)" }
    public var kind: String
    public var name: String
    public var sensitivity: AssetSensitivity
}

public struct NeighbourVO: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var posture: Posture
    public var planReviewedOn: String?
    public var planCurrency: PlanCurrency
}

public struct RoleVO: Sendable, Hashable, Identifiable {
    public var id: String { code }
    public var code: String
    public var name: String
    public var roleDescription: String
    public var priorityRank: Int
    public var sourceRef: String
}

public struct TaskLineVO: Sendable, Hashable, Identifiable {
    public var id: String
    public var roleCode: String
    public var phase: TaskPhase
    public var text: String
    public var sourceRef: String
}

/// Everything the Ask feature knows about a hub, fetched by explicit lookup —
/// never by text retrieval (ADR-004). Already privacy-filtered on construction.
public struct HubFactsVO: Sendable {
    public var hubID: String
    public var name: String
    public var taName: String
    public var address: String
    public var viewLevel: ViewLevel
    public var posture: Posture
    public var drivers: [SituationDriver]
    public var planReviewedOn: String?
    public var planCurrency: PlanCurrency
    public var planURL: String?
    public var hasPublishedPlan: Bool
    public var assets: [HubAssetVO]
    /// Rows the gate removed. A count is not an address, and saying "3 withheld"
    /// is more honest than pretending the plan lists nothing.
    public var restrictedWithheldCount: Int
    public var neighbours: [NeighbourVO]
    public var roles: [RoleVO]
    public var kitContents: [String]

    public var hubRecordCitation: CitationVO {
        CitationVO(
            kind: .hubRecord,
            sourceRef: "HubNode corpus — \(name)",
            detail: "hub record",
            reviewedOn: planReviewedOn
        )
    }
}

// MARK: - Result

/// Output of `answer_question` (architecture.md §6) as the board consumes it.
public struct AskResultVO: Sendable, Identifiable {
    public enum Mode: String, Sendable {
        case summarised
        case notSummarised
    }

    public var id = UUID()
    public var question: String
    public var hubID: String
    public var hubName: String
    public var viewLevel: ViewLevel
    public var intent: AskIntent
    public var mode: Mode
    /// Prose when a model summarised; the deterministic grounded answer otherwise.
    public var answer: String
    /// Always populated, always verbatim. This is what survives a cold model.
    public var passages: [RetrievedPassageVO]
    public var citations: [CitationVO]
    public var unknowns: [String]
    public var planReviewedOn: String?
    public var planCurrency: PlanCurrency

    public var isDegraded: Bool { mode == .notSummarised }

    public var modeLabel: String {
        switch mode {
        case .summarised: "Summarised by local model · every claim cited below"
        case .notSummarised: "Not summarised — no model available. Retrieved passages shown verbatim."
        }
    }
}

// MARK: - Intent

/// Deterministic question classification. It picks which *lookup* runs, so it
/// stays in code: a model choosing its own data source is a model choosing what
/// the privacy gate applies to.
public enum AskIntent: String, Sendable, CaseIterable {
    case openDecision
    case setup
    case place
    case role
    case neighbours
    case plan
    case general

    public var title: String {
        switch self {
        case .openDecision: "Opening decision"
        case .setup: "Setting up"
        case .place: "Places and resources"
        case .role: "Roles"
        case .neighbours: "Neighbouring hubs"
        case .plan: "Plan currency"
        case .general: "Hub Guide"
        }
    }
}
