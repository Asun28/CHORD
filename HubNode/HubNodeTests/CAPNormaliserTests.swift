import XCTest
@testable import HubNode

final class CAPNormaliserTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let env = CAPJSONEnvelope(
            externalID: "x1",
            msgType: "alert",
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            headline: "Test",
            description: "Desc",
            severity: "moderate",
            hazardClass: "weather",
            latitude: -41.3,
            longitude: 174.8,
            radiusMeters: 10_000
        )
        let data = try JSONEncoder().encode(env)
        // JSONEncoder uses different date strategy — use normaliser path via raw Data rebuilt
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(env)
        let item = RawFeedItem(
            externalID: "x1",
            observedAt: env.observedAt,
            payload: payload,
            contentType: "application/json"
        )
        let alert = try CAPNormaliser.normalise(item: item, source: FixtureCatalog.metservice)
        XCTAssertEqual(alert.externalID, "x1")
        XCTAssertEqual(alert.headline, "Test")
        XCTAssertEqual(alert.severity, .moderate)
        XCTAssertEqual(alert.hazardClass, .weather)
        XCTAssertEqual(alert.trustTier, .p1)
    }

    func testSpatialPointInPolygon() {
        let ring: [[Double]] = [
            [174.7, -41.4],
            [174.9, -41.4],
            [174.9, -41.2],
            [174.7, -41.2],
            [174.7, -41.4],
        ]
        XCTAssertTrue(SpatialMatch.pointInPolygon(lat: -41.3, lon: 174.8, ring: ring))
        XCTAssertFalse(SpatialMatch.pointInPolygon(lat: -40.5, lon: 174.8, ring: ring))
    }
}
