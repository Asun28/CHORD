# Feed adapter contract (for teammates)

You own the **adapters** (GeoNet, Metlink, GWRC, MetService CAP, HTML/WREMO status).  
Core owns **normalisation → CAP → posture → board**.

## Protocol

```swift
// HubNode/Feeds/FeedAdapter.swift

public struct SourceMetadata: Sendable {
    public var id: String
    public var name: String
    public var trustTier: TrustTier   // p0…p3
    public var cadence: TimeInterval   // expected poll interval
    public var attribution: String
}

public struct RawFeedItem: Sendable {
    public var externalID: String
    public var observedAt: Date
    public var payload: Data
    public var contentType: String     // application/json preferred
    public var msgTypeHint: CAPAlert.MsgType?  // alert | update | cancel
}

public protocol FeedAdapter: Sendable {
    var source: SourceMetadata { get }
    func fetch(at cursor: Date) async throws -> [RawFeedItem]
}
```

## Rules of the road

1. **Do not decide posture.** Never map severity → hub action in the adapter.
2. **Prefer the JSON envelope** below so core can normalise without per-feed special cases.
3. **Filter deleted quality at source if easy** (e.g. GeoNet `quality: deleted`); core also filters.
4. **Support Cancel/Update** via `msgType` + `references` when the upstream feed has them.
5. **Trust tiers (proposed):**

| Source | Tier | Notes |
|---|---|---|
| MetService CAP | P0/P1 | Authoritative weather |
| GeoNet | P1 | Official-adjacent |
| GWRC rivers / hazards | P1/P2 | Official regional |
| Metlink | P2 | Needs corroboration to raise posture alone |
| HTML status banners | P3 | Annotate only |

## Preferred payload: `CAPJSONEnvelope`

```json
{
  "externalID": "ws-southerly-warn-2",
  "msgType": "update",
  "observedAt": "2024-07-12T14:00:00Z",
  "expiresAt": "2024-07-13T18:00:00Z",
  "headline": "Severe weather warning — damaging southerly",
  "description": "…",
  "severity": "severe",
  "urgency": "immediate",
  "certainty": "observed",
  "hazardClass": "weather",
  "quality": null,
  "references": ["ws-southerly-warn-1"],
  "latitude": -41.29,
  "longitude": 174.78,
  "radiusMeters": 60000,
  "areaPolygon": [[174.7, -41.35], [174.9, -41.35], [174.9, -41.2], [174.7, -41.2], [174.7, -41.35]]
}
```

Enums (strings):

- `msgType`: `alert` | `update` | `cancel`
- `severity`: `unknown` | `minor` | `moderate` | `severe` | `extreme`
- `hazardClass`: `quake` | `weather` | `road` | `river` | `other`

GeoJSON Feature (GeoNet-shaped) is also accepted by `CAPNormaliser` without the envelope.

## Wiring into the app

```swift
// AppModel / PollLoop
pollLoop.setAdapters([
    YourGeoNetAdapter(),
    YourMetlinkAdapter(),
    // keep fixtures for demo fallback:
    // DemoReplay.adapters()
])
```

Replay cursor: `fetch(at:)` should only return items with `observedAt <= cursor` so demo scrubbing works the same as live.

## Fixtures

While NZ is quiet, capture real responses under `HubNode/Resources/Fixtures/` and implement `fetch` to read them when offline. Core ships a scripted southerly/river/quake sequence in `DemoReplay` for the pitch.
