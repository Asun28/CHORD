import XCTest
@testable import HubNode

final class PostureEngineTests: XCTestCase {
 let newtownLat = -41.311
 let newtownLon = 174.779

 func testGreenWhenEmpty() {
 let snap = PostureEngine.recompute(
 hubID: "newtown",
 hubLatitude: newtownLat,
 hubLongitude: newtownLon,
 alerts: [],
 sourceCadences: [:],
 at: .now
 )
 XCTAssertEqual(snap.posture, .green)
 }

 func testP1AdvisoryRaisesWatch() {
 let alert = CAPAlert(
 sourceID: "metservice",
 externalID: "adv1",
 observedAt: .now,
 headline: "Wind advisory",
 severity: .minor,
 hazardClass: .weather,
 latitude: newtownLat,
 longitude: newtownLon,
 radiusMeters: 50_000,
 trustTier: .p1,
 attribution: "MetService"
 )
 let snap = PostureEngine.recompute(
 hubID: "newtown",
 hubLatitude: newtownLat,
 hubLongitude: newtownLon,
 alerts: [alert],
 sourceCadences: ["metservice": 300],
 at: .now
 )
 XCTAssertEqual(snap.posture, .watch)
 }

 func testP1ModerateRaisesAct() {
 let alert = CAPAlert(
 sourceID: "metservice",
 externalID: "warn1",
 observedAt: .now,
 headline: "Severe weather",
 severity: .moderate,
 hazardClass: .weather,
 latitude: newtownLat,
 longitude: newtownLon,
 radiusMeters: 50_000,
 trustTier: .p1,
 attribution: "MetService"
 )
 let snap = PostureEngine.recompute(
 hubID: "newtown",
 hubLatitude: newtownLat,
 hubLongitude: newtownLon,
 alerts: [alert],
 sourceCadences: ["metservice": 300],
 at: .now
 )
 XCTAssertEqual(snap.posture, .act)
 }

 func testP1SevereRaisesRespond() {
 let alert = CAPAlert(
 sourceID: "geonet",
 externalID: "eq1",
 observedAt: .now,
 headline: "M5.8",
 severity: .severe,
 hazardClass: .quake,
 latitude: newtownLat,
 longitude: newtownLon,
 radiusMeters: 100_000,
 trustTier: .p1,
 attribution: "GeoNet"
 )
 let snap = PostureEngine.recompute(
 hubID: "newtown",
 hubLatitude: newtownLat,
 hubLongitude: newtownLon,
 alerts: [alert],
 sourceCadences: ["geonet": 60],
 at: .now
 )
 XCTAssertEqual(snap.posture, .respond)
 }

 func testLoneP2DoesNotRaise() {
 let alert = CAPAlert(
 sourceID: "metlink",
 externalID: "r1",
 observedAt: .now,
 headline: "Bus delay",
 severity: .minor,
 hazardClass: .road,
 latitude: newtownLat,
 longitude: newtownLon,
 radiusMeters: 5_000,
 trustTier: .p2,
 attribution: "Metlink"
 )
 let snap = PostureEngine.recompute(
 hubID: "newtown",
 hubLatitude: newtownLat,
 hubLongitude: newtownLon,
 alerts: [alert],
 sourceCadences: ["metlink": 120],
 at: .now
 )
 XCTAssertEqual(snap.posture, .green)
 XCTAssertEqual(snap.drivers.count, 1)
 }

 func testCorroboratedP2RaisesWatch() {
 let a = CAPAlert(
 sourceID: "metlink",
 externalID: "r1",
 observedAt: .now,
 headline: "Road",
 severity: .minor,
 hazardClass: .road,
 latitude: newtownLat,
 longitude: newtownLon,
 radiusMeters: 8_000,
 trustTier: .p2,
 attribution: "Metlink"
 )
 let b = CAPAlert(
 sourceID: "nzta",
 externalID: "r2",
 observedAt: .now,
 headline: "Road 2",
 severity: .minor,
 hazardClass: .road,
 latitude: newtownLat,
 longitude: newtownLon,
 radiusMeters: 8_000,
 trustTier: .p2,
 attribution: "NZTA"
 )
 let snap = PostureEngine.recompute(
 hubID: "newtown",
 hubLatitude: newtownLat,
 hubLongitude: newtownLon,
 alerts: [a, b],
 sourceCadences: ["metlink": 120, "nzta": 300],
 at: .now
 )
 XCTAssertEqual(snap.posture, .watch)
 }

 func testP3AnnotatesOnly() {
 let alert = CAPAlert(
 sourceID: "wremo-status",
 externalID: "banner",
 observedAt: .now.addingTimeInterval(-30 * 86_400),
 headline: "No emergencies",
 severity: .unknown,
 hazardClass: .other,
 trustTier: .p3,
 attribution: "WREMO"
 )
 let snap = PostureEngine.recompute(
 hubID: "newtown",
 hubLatitude: newtownLat,
 hubLongitude: newtownLon,
 alerts: [alert],
 sourceCadences: ["wremo-status": 3600],
 at: .now
 )
 XCTAssertEqual(snap.posture, .green)
 XCTAssertTrue(snap.drivers.isEmpty)
 XCTAssertEqual(snap.annotations.count, 1)
 XCTAssertTrue(snap.annotations[0].isStale)
 }

 func testDeletedQualityExcluded() {
 let alert = CAPAlert(
 sourceID: "geonet",
 externalID: "eq-del",
 observedAt: .now,
 headline: "Retracted",
 severity: .severe,
 hazardClass: .quake,
 quality: "deleted",
 latitude: newtownLat,
 longitude: newtownLon,
 radiusMeters: 100_000,
 trustTier: .p1,
 attribution: "GeoNet"
 )
 let snap = PostureEngine.recompute(
 hubID: "newtown",
 hubLatitude: newtownLat,
 hubLongitude: newtownLon,
 alerts: [alert],
 sourceCadences: ["geonet": 60],
 at: .now
 )
 XCTAssertEqual(snap.posture, .green)
 }

 func testFarQuakeDoesNotAffectHub() {
 let alert = CAPAlert(
 sourceID: "geonet",
 externalID: "eq-akl",
 observedAt: .now,
 headline: "Auckland quake",
 severity: .severe,
 hazardClass: .quake,
 latitude: -36.85,
 longitude: 174.76,
 radiusMeters: 40_000,
 trustTier: .p1,
 attribution: "GeoNet"
 )
 let snap = PostureEngine.recompute(
 hubID: "newtown",
 hubLatitude: newtownLat,
 hubLongitude: newtownLon,
 alerts: [alert],
 sourceCadences: ["geonet": 60],
 at: .now
 )
 XCTAssertEqual(snap.posture, .green)
 }
}
