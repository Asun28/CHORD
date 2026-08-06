import Foundation

/// Raw item from a feed adapter before CAP normalisation.
/// Teammates implement `FeedAdapter`; core owns normalisation and posture.
public struct RawFeedItem: Sendable, Identifiable {
 public var id: String
 public var externalID: String
 public var observedAt: Date
 public var payload: Data
 public var contentType: String // "application/json", "application/cap+xml", etc.
 public var msgTypeHint: CAPAlert.MsgType?

 public init(
 id: String? = nil,
 externalID: String,
 observedAt: Date,
 payload: Data,
 contentType: String = "application/json",
 msgTypeHint: CAPAlert.MsgType? = nil
 ) {
 self.id = id ?? externalID
 self.externalID = externalID
 self.observedAt = observedAt
 self.payload = payload
 self.contentType = contentType
 self.msgTypeHint = msgTypeHint
 }
}

public struct SourceMetadata: Sendable, Identifiable, Hashable {
 public var id: String
 public var name: String
 public var trustTier: TrustTier
 public var cadence: TimeInterval
 public var attribution: String
 public var licence: String?

 public init(
 id: String,
 name: String,
 trustTier: TrustTier,
 cadence: TimeInterval,
 attribution: String,
 licence: String? = nil
 ) {
 self.id = id
 self.name = name
 self.trustTier = trustTier
 self.cadence = cadence
 self.attribution = attribution
 self.licence = licence
 }
}

/// Contract for teammate feed adapters (Metlink, GeoNet, GWRC, HTML, …).
/// Adapters must not decide posture. Only fetch raw items.
public protocol FeedAdapter: Sendable {
 var source: SourceMetadata { get }
 func fetch(at cursor: Date) async throws -> [RawFeedItem]
}

public extension FeedAdapter {
 var sourceID: String { source.id }
 var trustTier: TrustTier { source.trustTier }
 var cadence: TimeInterval { source.cadence }
}

/// Feed operating mode (architecture.md §1).
public enum FeedMode: String, Codable, Sendable, CaseIterable {
 case origin // poll sources directly
 case relay // poll a regional relay URL
}
