import Foundation
import CoreLocation

public enum SpatialMatch {
    public static func distanceMeters(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let a = CLLocation(latitude: lat1, longitude: lon1)
        let b = CLLocation(latitude: lat2, longitude: lon2)
        return a.distance(from: b)
    }

    /// Whether an observation geometry intersects a hub under class-specific rules.
    public static func affectsHub(
        alert: CAPAlert,
        hubLatitude: Double,
        hubLongitude: Double
    ) -> Bool {
        switch alert.hazardClass {
        case .quake:
            guard let lat = alert.latitude, let lon = alert.longitude else { return false }
            let radius = alert.radiusMeters ?? 50_000
            return distanceMeters(lat1: hubLatitude, lon1: hubLongitude, lat2: lat, lon2: lon) <= radius

        case .weather:
            if let poly = alert.areaPolygon, poly.count >= 3 {
                return pointInPolygon(
                    lat: hubLatitude, lon: hubLongitude,
                    ring: poly
                )
            }
            // Fall back to radius/point if no polygon
            fallthrough

        case .road:
            guard let lat = alert.latitude, let lon = alert.longitude else {
                // Regional warning without geometry: treat as regional (affects all)
                return alert.hazardClass == .weather
            }
            let radius = alert.radiusMeters ?? (alert.hazardClass == .road ? 5_000 : 30_000)
            return distanceMeters(lat1: hubLatitude, lon1: hubLongitude, lat2: lat, lon2: lon) <= radius

        case .river:
            guard let lat = alert.latitude, let lon = alert.longitude else { return false }
            let radius = alert.radiusMeters ?? 8_000
            return distanceMeters(lat1: hubLatitude, lon1: hubLongitude, lat2: lat, lon2: lon) <= radius

        case .other:
            guard let lat = alert.latitude, let lon = alert.longitude else { return true }
            let radius = alert.radiusMeters ?? 25_000
            return distanceMeters(lat1: hubLatitude, lon1: hubLongitude, lat2: lat, lon2: lon) <= radius
        }
    }

    /// Ray-casting point-in-polygon. Ring is [[lon, lat], ...].
    public static func pointInPolygon(lat: Double, lon: Double, ring: [[Double]]) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let xi = ring[i].count > 1 ? ring[i][0] : 0
            let yi = ring[i].count > 1 ? ring[i][1] : 0
            let xj = ring[j].count > 1 ? ring[j][0] : 0
            let yj = ring[j].count > 1 ? ring[j][1] : 0
            let intersect = ((yi > lat) != (yj > lat))
                && (lon < (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }
}
