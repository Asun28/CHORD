import Foundation

/// Turns adapter payloads into CAPAlert values.
/// Models never parse GeoJSON — this code does (architecture.md §2).
public enum CAPNormaliser {
    public static func normalise(
        item: RawFeedItem,
        source: SourceMetadata,
        fetchedAt: Date = .now
    ) throws -> CAPAlert {
        // Prefer structured JSON envelope used by fixtures and future adapters.
        if item.contentType.contains("json") || item.contentType.contains("geo+json") {
            if let envelope = try? JSONDecoder.cap.decode(CAPJSONEnvelope.self, from: item.payload) {
                return envelope.asCAPAlert(source: source, item: item, fetchedAt: fetchedAt)
            }
            // GeoNet-style Feature
            if let feature = try? JSONDecoder.cap.decode(GeoJSONFeature.self, from: item.payload) {
                return feature.asCAPAlert(source: source, item: item, fetchedAt: fetchedAt)
            }
        }

        // Fallback: opaque payload with metadata only
        return CAPAlert(
            sourceID: source.id,
            externalID: item.externalID,
            msgType: item.msgTypeHint ?? .alert,
            observedAt: item.observedAt,
            fetchedAt: fetchedAt,
            headline: "Update from \(source.name)",
            description: String(data: item.payload, encoding: .utf8) ?? "",
            hazardClass: .other,
            trustTier: source.trustTier,
            attribution: source.attribution,
            rawJSON: String(data: item.payload, encoding: .utf8)
        )
    }
}

// MARK: - Fixture / adapter JSON envelope

public struct CAPJSONEnvelope: Codable, Sendable {
    public var externalID: String
    public var msgType: String?
    public var observedAt: Date
    public var expiresAt: Date?
    public var headline: String
    public var description: String?
    public var instruction: String?
    public var severity: String?
    public var urgency: String?
    public var certainty: String?
    public var hazardClass: String?
    public var quality: String?
    public var references: [String]?
    public var latitude: Double?
    public var longitude: Double?
    public var radiusMeters: Double?
    public var areaPolygon: [[Double]]?

    func asCAPAlert(source: SourceMetadata, item: RawFeedItem, fetchedAt: Date) -> CAPAlert {
        CAPAlert(
            sourceID: source.id,
            externalID: externalID,
            msgType: CAPAlert.MsgType(rawValue: msgType ?? "") ?? item.msgTypeHint ?? .alert,
            observedAt: observedAt,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            headline: headline,
            description: description ?? "",
            instruction: instruction,
            severity: CAPAlert.Severity(rawValue: severity ?? "") ?? .unknown,
            urgency: CAPAlert.Urgency(rawValue: urgency ?? "") ?? .unknown,
            certainty: CAPAlert.Certainty(rawValue: certainty ?? "") ?? .unknown,
            hazardClass: CAPAlert.HazardClass(rawValue: hazardClass ?? "") ?? .other,
            quality: quality,
            references: references ?? [],
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            areaPolygon: areaPolygon,
            trustTier: source.trustTier,
            attribution: source.attribution,
            rawJSON: String(data: item.payload, encoding: .utf8)
        )
    }
}

// MARK: - Minimal GeoNet Feature support

struct GeoJSONFeature: Codable {
    var type: String?
    var id: String?
    var geometry: Geometry?
    var properties: Properties?

    struct Geometry: Codable {
        var type: String?
        var coordinates: [Double]?  // [lon, lat, depth?]
    }

    struct Properties: Codable {
        var publicID: String?
        var time: Date?
        var magnitude: Double?
        var mmi: Int?
        var locality: String?
        var quality: String?
        var intensity: String?
    }

    func asCAPAlert(source: SourceMetadata, item: RawFeedItem, fetchedAt: Date) -> CAPAlert {
        let props = properties
        let coords = geometry?.coordinates
        let lon = coords?.first
        let lat = coords?.count ?? 0 > 1 ? coords?[1] : nil
        let mag = props?.magnitude
        let mmi = props?.mmi
        let radius: Double? = mmi.map { quakeRadiusMeters(mmi: $0) }
        let severity: CAPAlert.Severity = {
            guard let mag else { return .unknown }
            if mag >= 6 { return .extreme }
            if mag >= 5 { return .severe }
            if mag >= 4 { return .moderate }
            return .minor
        }()
        let external = props?.publicID ?? id ?? item.externalID
        let locality = props?.locality ?? "unknown locality"
        let headline: String
        if let mag {
            headline = String(format: "M%.1f earthquake near %@", mag, locality)
        } else {
            headline = "Earthquake near \(locality)"
        }
        return CAPAlert(
            sourceID: source.id,
            externalID: external,
            msgType: item.msgTypeHint ?? .alert,
            observedAt: props?.time ?? item.observedAt,
            fetchedAt: fetchedAt,
            headline: headline,
            description: "MMI \(mmi.map(String.init) ?? "—"); quality \(props?.quality ?? "—")",
            severity: severity,
            urgency: .immediate,
            certainty: .observed,
            hazardClass: .quake,
            quality: props?.quality,
            latitude: lat,
            longitude: lon,
            radiusMeters: radius,
            trustTier: source.trustTier,
            attribution: source.attribution,
            rawJSON: String(data: item.payload, encoding: .utf8)
        )
    }
}

func quakeRadiusMeters(mmi: Int) -> Double {
    // Rough operational radii for hub matching (not a shaking model).
    switch mmi {
    case ...3: return 15_000
    case 4: return 40_000
    case 5: return 80_000
    case 6: return 150_000
    default: return 250_000
    }
}

extension JSONDecoder {
    static let cap: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                if let date = ISO8601DateFormatter.cap.date(from: s) { return date }
                if let date = ISO8601DateFormatter.capFractional.date(from: s) { return date }
            }
            if let t = try? c.decode(Double.self) {
                // GeoNet sometimes uses ms
                if t > 1e12 { return Date(timeIntervalSince1970: t / 1000) }
                return Date(timeIntervalSince1970: t)
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognised date")
        }
        return d
    }()
}

extension ISO8601DateFormatter {
    static let cap: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let capFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
