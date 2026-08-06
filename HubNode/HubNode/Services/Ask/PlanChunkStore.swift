import Foundation

/// Community Response Plan prose, indexed by hub slug.
///
/// Why a dictionary and not a search index: the scoping rule matters more than
/// the ranking. A lookup asks for *one* hub's passages, so cross-hub leakage is
/// structurally impossible rather than filtered after the fact (architecture.md §9).
/// The file is parsed once per process — O(n) on first touch, O(1) per hub after.
@MainActor
final class PlanChunkStore {
    static let shared = PlanChunkStore()

    private var byHubID: [String: [RetrievedPassageVO]] = [:]
    private var didLoad = false
    private(set) var loadError: String?

    init() {}

    /// Test seam — inject fixture passages instead of reading the bundle.
    init(passages: [RetrievedPassageVO]) {
        byHubID = Dictionary(grouping: passages) { $0.hubID ?? "" }
        didLoad = true
    }

    /// Plan passages for exactly this hub. Never falls back to a neighbour:
    /// an absent plan must read as absent (architecture.md §7).
    func passages(forHubID hubID: String) -> [RetrievedPassageVO] {
        loadIfNeeded()
        return byHubID[hubID] ?? []
    }

    func hasPlanProse(forHubID hubID: String) -> Bool {
        !passages(forHubID: hubID).isEmpty
    }

    var hubCount: Int {
        loadIfNeeded()
        return byHubID.count
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        do {
            let url = try CorpusBootstrap.resourceURL("plan_chunks", ext: "jsonl")
            let text = try String(contentsOf: url, encoding: .utf8)
            let decoder = JSONDecoder()
            var grouped: [String: [RetrievedPassageVO]] = [:]
            for line in text.split(separator: "\n") where !line.isEmpty {
                guard let data = line.data(using: .utf8),
                      let dto = try? decoder.decode(PlanChunkDTO.self, from: data)
                else { continue }
                grouped[dto.hubID, default: []].append(dto.asPassage())
            }
            byHubID = grouped
            loadError = nil
            print("HubNode: plan prose loaded for \(grouped.count) hubs")
        } catch {
            byHubID = [:]
            loadError = error.localizedDescription
            // Not fatal: Ask still answers from the regional guide and hub facts.
            print("HubNode: plan prose unavailable (\(error.localizedDescription)) — guide-only retrieval")
        }
    }
}

/// Wire format for plan_chunks.jsonl (built by tools/build_plan_chunks.py).
private struct PlanChunkDTO: Codable {
    var hubID: String
    var section: String
    var part: Int
    var text: String
    var sourceRef: String
    var reviewedOn: String?

    enum CodingKeys: String, CodingKey {
        case hubID = "hub_id"
        case section
        case part
        case text
        case sourceRef = "source_ref"
        case reviewedOn = "reviewed_on"
    }

    func asPassage() -> RetrievedPassageVO {
        RetrievedPassageVO(
            id: "\(hubID)#\(part)",
            origin: .hubPlan,
            hubID: hubID,
            section: section,
            text: text,
            sourceRef: sourceRef,
            reviewedOn: reviewedOn.nonEmptyTrimmed
        )
    }
}
