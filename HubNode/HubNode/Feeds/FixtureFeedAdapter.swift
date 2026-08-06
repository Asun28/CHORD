import Foundation

/// Built-in demo sources + southerly/quake replay fixtures.
enum FixtureCatalog {
 static let geonet = SourceMetadata(
 id: "geonet",
 name: "GeoNet",
 trustTier: .p1,
 cadence: 60,
 attribution: "GeoNet / GNS Science"
 )
 static let metservice = SourceMetadata(
 id: "metservice",
 name: "MetService",
 trustTier: .p1,
 cadence: 300,
 attribution: "MetService NZ"
 )
 static let gwrcRivers = SourceMetadata(
 id: "gwrc-rivers",
 name: "GWRC Rivers",
 trustTier: .p1,
 cadence: 900,
 attribution: "Greater Wellington Regional Council"
 )
 static let metlink = SourceMetadata(
 id: "metlink",
 name: "Metlink",
 trustTier: .p2,
 cadence: 120,
 attribution: "Metlink / GWRC"
 )
 static let wremoBanner = SourceMetadata(
 id: "wremo-status",
 name: "WREMO Status",
 trustTier: .p3,
 cadence: 3600,
 attribution: "WREMO (HTML)"
 )

 static var sources: [SourceMetadata] {
 [geonet, metservice, gwrcRivers, metlink, wremoBanner]
 }
}

/// Emits pre-scripted CAP envelopes for the demo replay.
struct FixtureFeedAdapter: FeedAdapter {
 let source: SourceMetadata
 private let events: [CAPJSONEnvelope]
 var isPaused: Bool = false

 init(source: SourceMetadata, events: [CAPJSONEnvelope], isPaused: Bool = false) {
 self.source = source
 self.events = events
 self.isPaused = isPaused
 }

 func fetch(at cursor: Date) async throws -> [RawFeedItem] {
 if isPaused { return [] }
 let encoder = JSONEncoder()
 encoder.dateEncodingStrategy = .iso8601
 return try events
 .filter { $0.observedAt <= cursor }
 .map { env in
 let data = try encoder.encode(env)
 return RawFeedItem(
 externalID: env.externalID,
 observedAt: env.observedAt,
 payload: data,
 contentType: "application/json",
 msgTypeHint: CAPAlert.MsgType(rawValue: env.msgType ?? "alert")
 )
 }
 }
}

enum DemoReplay {
 /// A Wellington-region southerly + river + quake sequence for pitch demo.
 /// Coordinates centre on Wellington / Hutt / south coast.
 static func adapters() -> [FixtureFeedAdapter] {
 let cal = Calendar.current
 let base = cal.date(from: DateComponents(year: 2024, month: 7, day: 12, hour: 6, minute: 0))!
 func t(_ hours: Double) -> Date {
 base.addingTimeInterval(hours * 3600)
 }

 // Wellington CBD-ish polygon (simplified)
 let wellingtonPoly: [[Double]] = [
 [174.70, -41.35],
 [174.90, -41.35],
 [174.90, -41.20],
 [174.70, -41.20],
 [174.70, -41.35],
 ]

 let weather: [CAPJSONEnvelope] = [
 CAPJSONEnvelope(
 externalID: "ws-southerly-adv-1",
 msgType: "alert",
 observedAt: t(0),
 expiresAt: t(24),
 headline: "Strong wind advisory - Wellington",
 description: "Gale northerly easing, strong southerly developing this evening.",
 severity: "minor",
 urgency: "expected",
 certainty: "likely",
 hazardClass: "weather",
 latitude: -41.29,
 longitude: 174.78,
 radiusMeters: 40_000,
 areaPolygon: wellingtonPoly
 ),
 CAPJSONEnvelope(
 externalID: "ws-southerly-warn-1",
 msgType: "update",
 observedAt: t(4),
 expiresAt: t(30),
 headline: "Severe southerly watch - Wellington region",
 description: "Damaging southerly winds expected. Coastal and elevated exposure.",
 severity: "moderate",
 urgency: "expected",
 certainty: "likely",
 hazardClass: "weather",
 latitude: -41.29,
 longitude: 174.78,
 radiusMeters: 50_000,
 areaPolygon: wellingtonPoly
 ),
 CAPJSONEnvelope(
 externalID: "ws-southerly-warn-2",
 msgType: "update",
 observedAt: t(8),
 expiresAt: t(36),
 headline: "Severe weather warning. Damaging southerly",
 description: "Damaging southerly in force. Power and tree damage possible.",
 severity: "severe",
 urgency: "immediate",
 certainty: "observed",
 hazardClass: "weather",
 latitude: -41.29,
 longitude: 174.78,
 radiusMeters: 60_000,
 areaPolygon: wellingtonPoly
 ),
 ]

 let river: [CAPJSONEnvelope] = [
 CAPJSONEnvelope(
 externalID: "hutt-taita-rising",
 msgType: "alert",
 observedAt: t(5),
 expiresAt: t(40),
 headline: "Hutt River at Taita. Rising",
 description: "River level rising after intense rain. Monitor low-lying areas.",
 severity: "moderate",
 urgency: "expected",
 certainty: "observed",
 hazardClass: "river",
 latitude: -41.18,
 longitude: 174.96,
 radiusMeters: 10_000
 ),
 CAPJSONEnvelope(
 externalID: "hutt-taita-alarm",
 msgType: "update",
 observedAt: t(9),
 expiresAt: t(48),
 headline: "Hutt River at Taita. Alarm level",
 description: "River at alarm. Flooding of adjacent land possible.",
 severity: "severe",
 urgency: "immediate",
 certainty: "observed",
 hazardClass: "river",
 latitude: -41.18,
 longitude: 174.96,
 radiusMeters: 12_000
 ),
 ]

 let roads: [CAPJSONEnvelope] = [
 CAPJSONEnvelope(
 externalID: "metlink-route1-delay",
 msgType: "alert",
 observedAt: t(6),
 expiresAt: t(20),
 headline: "Route 1 delays. Weather related",
 description: "Significant delays on key Metlink routes across the city.",
 severity: "minor",
 urgency: "immediate",
 certainty: "observed",
 hazardClass: "road",
 latitude: -41.30,
 longitude: 174.78,
 radiusMeters: 8_000
 ),
 CAPJSONEnvelope(
 externalID: "sh2-slip-petone",
 msgType: "alert",
 observedAt: t(7.5),
 expiresAt: t(48),
 headline: "SH2 Petone. Slip, lane closed",
 description: "Slip debris; expect long delays between Petone and Ngauranga.",
 severity: "moderate",
 urgency: "immediate",
 certainty: "observed",
 hazardClass: "road",
 latitude: -41.23,
 longitude: 174.88,
 radiusMeters: 6_000
 ),
 ]

 let quake: [CAPJSONEnvelope] = [
 CAPJSONEnvelope(
 externalID: "geonet-demo-m58",
 msgType: "alert",
 observedAt: t(10),
 expiresAt: t(72),
 headline: "M5.8 earthquake near Wellington",
 description: "Felt widely. Check for injuries and building damage before opening hubs.",
 severity: "severe",
 urgency: "immediate",
 certainty: "observed",
 hazardClass: "quake",
 quality: "best",
 latitude: -41.30,
 longitude: 174.80,
 radiusMeters: 100_000
 ),
 ]

 let banner: [CAPJSONEnvelope] = [
 CAPJSONEnvelope(
 externalID: "wremo-banner-quiet",
 msgType: "alert",
 observedAt: t(-24 * 30), // ~30 days stale. Honesty demo
 expiresAt: nil,
 headline: "No emergencies in the Wellington Region",
 description: "Hand-updated status banner (demo fixture). Intentionally stale.",
 severity: "unknown",
 urgency: "past",
 certainty: "unknown",
 hazardClass: "other"
 ),
 ]

 return [
 FixtureFeedAdapter(source: FixtureCatalog.metservice, events: weather),
 FixtureFeedAdapter(source: FixtureCatalog.gwrcRivers, events: river),
 FixtureFeedAdapter(source: FixtureCatalog.metlink, events: roads),
 FixtureFeedAdapter(source: FixtureCatalog.geonet, events: quake),
 FixtureFeedAdapter(source: FixtureCatalog.wremoBanner, events: banner),
 ]
 }

 static var timelineStart: Date {
 Calendar.current.date(from: DateComponents(year: 2024, month: 7, day: 12, hour: 6))!
 }

 static var timelineEnd: Date {
 timelineStart.addingTimeInterval(14 * 3600)
 }
}
