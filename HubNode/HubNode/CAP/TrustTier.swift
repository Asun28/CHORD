import Foundation

/// Trust ladder from architecture.md §5 / scope v4 §6.
/// P0/P1 may raise posture alone; P2 needs corroboration; P3 annotates only.
public enum TrustTier: Int, Codable, Sendable, Comparable {
    case p0 = 0  // authoritative
    case p1 = 1  // official-adjacent
    case p2 = 2  // credible secondary — corroborate
    case p3 = 3  // open web / crowd — signal only

    public static func < (lhs: TrustTier, rhs: TrustTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var mayRaisePostureAlone: Bool { self == .p0 || self == .p1 }
    public var annotatesOnly: Bool { self == .p3 }

    public var label: String {
        switch self {
        case .p0: "P0 authoritative"
        case .p1: "P1 official"
        case .p2: "P2 secondary"
        case .p3: "P3 signal"
        }
    }
}
