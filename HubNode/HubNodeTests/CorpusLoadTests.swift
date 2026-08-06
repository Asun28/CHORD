import XCTest
@testable import HubNode

final class CorpusLoadTests: XCTestCase {
    func testLoadMapItemsFromBundleOrSourceTree() throws {
        let items = try CorpusBootstrap.loadMapItems()
        XCTAssertGreaterThanOrEqual(items.count, 100, "Expected ~125 hubs, got \(items.count)")
        let newtown = items.first { $0.id.contains("newtown") }
        XCTAssertNotNil(newtown, "Newtown hub should exist")
        if let n = newtown {
            XCTAssertTrue(n.latitude < 0, "NZ is southern hemisphere")
            XCTAssertTrue(n.longitude > 174 && n.longitude < 176)
            print("Newtown @ \(n.latitude), \(n.longitude) neighbours=\(n.neighbourIDs.count)")
        }
        // Sample range covers Wellington region
        let lats = items.map(\.latitude)
        let lons = items.map(\.longitude)
        XCTAssertTrue(lats.min()! < -40.5)
        XCTAssertTrue(lats.max()! > -41.5 || lats.min()! < -41)
        XCTAssertTrue(lons.min()! > 174)
        XCTAssertTrue(lons.max()! < 177)
    }
}
