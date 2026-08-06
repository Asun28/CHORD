import Foundation
import CoreLocation
import SwiftUI

/// Lightweight, non-SwiftData pin model for the map.
/// Loaded directly from hubs.csv so MapKit never depends on @Query refresh.
struct HubMapItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let taName: String
    let address: String
    let latitude: Double
    let longitude: Double
    let crpURL: String?
    let crpReviewedOn: String?
    let neighbourIDs: [String]
    let nAssetsPublic: Int
    let nAssetsRestricted: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var planCurrency: PlanCurrency {
        PlanCurrency.from(reviewedOn: crpReviewedOn)
    }
}
