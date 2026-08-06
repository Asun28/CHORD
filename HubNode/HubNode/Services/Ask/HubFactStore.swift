import Foundation
import SwiftData

// MARK: - Flow: hub facts + gated retrieval
/// Only route Ask uses for hub data (architecture.md §8, ADR-004).
/// 1. Structured facts from tables (assets, neighbours, roles) — never from the model.
/// 2. Plan/guide prose retrieved only after privacy filter: restricted facility
///    *names* often appear inside plan_chunks, so redaction must sit on the
///    retrieval path, not only the asset table.
@MainActor
final class HubFactStore {
    private let context: ModelContext
    private let planChunks: PlanChunkStore

    init(context: ModelContext, planChunks: PlanChunkStore? = nil) {
        self.context = context
        self.planChunks = planChunks ?? PlanChunkStore.shared
    }

    // MARK: - Facts

    func facts(
        for hub: Hub,
        viewLevel: ViewLevel,
        posture: Posture,
        drivers: [SituationDriver]
    ) -> HubFactsVO {
        let disclosed = disclosableAssets(for: hub, viewLevel: viewLevel)
        return HubFactsVO(
            hubID: hub.id,
            name: hub.name,
            taName: hub.taName,
            address: hub.address,
            viewLevel: viewLevel,
            posture: posture,
            drivers: drivers,
            planReviewedOn: hub.crpReviewedOn.nonEmptyTrimmed,
            planCurrency: hub.planCurrency,
            planURL: hub.crpURL.nonEmptyTrimmed,
            hasPublishedPlan: hub.planCurrency != .missing,
            assets: disclosed.assets,
            restrictedWithheldCount: disclosed.withheldCount,
            neighbours: neighbours(of: hub),
            roles: roles(),
            kitContents: kitContents(of: hub)
        )
    }

    // MARK: - Privacy gate

    struct DisclosedAssets: Sendable {
        var assets: [HubAssetVO]
        var withheldCount: Int
    }

    /// Board view gets public rows only. The restricted rows are never mapped
    /// into a VO, so they cannot be serialised into a prompt by accident.
    func disclosableAssets(for hub: Hub, viewLevel: ViewLevel) -> DisclosedAssets {
        switch viewLevel {
        case .coordinator:
            let rows = assetRows(for: hub, sensitivity: nil)
            return DisclosedAssets(
                assets: rows.map(Self.asVO).sorted { $0.name < $1.name },
                withheldCount: 0
            )
        case .public:
            let rows = assetRows(for: hub, sensitivity: .public)
            // Second gate on the name itself: the corpus classifier is pattern
            // based, so a row mislabelled `public` still must not name a rest home.
            let allowed = rows.filter { !RestrictedVocabulary.matches($0.name) }
            let withheld = hub.nAssetsRestricted + (rows.count - allowed.count)
            return DisclosedAssets(
                assets: allowed.map(Self.asVO).sorted { $0.name < $1.name },
                withheldCount: withheld
            )
        }
    }

    /// Restricted names, used *only* to decide which prose to drop. Deliberately
    /// private: it never leaves this type.
    private func restrictedTerms(for hub: Hub) -> [String] {
        var terms: Set<String> = []
        for row in assetRows(for: hub, sensitivity: .restricted) {
            let full = row.name.collapsedWhitespace
            if full.count >= 6 { terms.insert(full) }
            // Plans write these as "Name, street, suburb". The name and the street
            // are the identifying parts; a bare suburb is not, and excluding it
            // would gut the passage set for no privacy gain.
            for part in full.split(separator: ",") {
                let piece = String(part).collapsedWhitespace
                guard piece.count >= 6 else { continue }
                let words = piece.split(separator: " ").count
                let hasNumber = piece.rangeOfCharacter(from: .decimalDigits) != nil
                if words >= 2 || hasNumber { terms.insert(piece) }
            }
        }
        return Array(terms)
    }

    private func assetRows(for hub: Hub, sensitivity: AssetSensitivity?) -> [HubAsset] {
        // Prefer the relationship on this hub — global fetch + inverse can miss
        // rows when the store was partially seeded.
        var rows = hub.assets
        if rows.isEmpty {
            let hubID = hub.id
            let all = (try? context.fetch(FetchDescriptor<HubAsset>())) ?? []
            rows = all.filter { $0.hub?.id == hubID }
        }
        if let sensitivity {
            rows = rows.filter { $0.sensitivity == sensitivity }
        }
        return rows
    }

    private static func asVO(_ row: HubAsset) -> HubAssetVO {
        HubAssetVO(kind: row.kind, name: row.name.collapsedWhitespace, sensitivity: row.sensitivity)
    }

    // MARK: - Relations and catalogues

    /// Neighbour identity by id lookup, not by text search. Unique-indexed, so
    /// this stays O(k log n) as the corpus grows past one region.
    func neighbours(of hub: Hub) -> [NeighbourVO] {
        hub.neighbourIDs.compactMap { id in
            if let row = hubRow(id: id) {
                let posture = row.situations
                    .sorted { $0.computedAt > $1.computedAt }
                    .first?.posture ?? .green
                return NeighbourVO(
                    id: row.id,
                    name: row.name,
                    posture: posture,
                    planReviewedOn: row.crpReviewedOn.nonEmptyTrimmed,
                    planCurrency: row.planCurrency
                )
            }
            // Fall back to map corpus if SwiftData row not seeded yet
            return nil
        }
    }

    func roles() -> [RoleVO] {
        let rows = (try? context.fetch(
            FetchDescriptor<RoleDef>(sortBy: [SortDescriptor(\.priorityRank)])
        )) ?? []
        return rows.map {
            RoleVO(
                code: $0.code,
                name: $0.name,
                roleDescription: $0.roleDescription,
                priorityRank: $0.priorityRank,
                sourceRef: $0.sourceRef
            )
        }
    }

    /// Instruction text always comes from WREMO's catalogue (ADR-005).
    func taskLines(phases: [TaskPhase], roleCode: String? = nil, limit: Int = 6) -> [TaskLineVO] {
        let rows = (try? context.fetch(FetchDescriptor<TaskTemplate>())) ?? []
        let phaseOrder = Dictionary(phases.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return rows
            .filter { phaseOrder[$0.phase] != nil }
            .filter { roleCode == nil || $0.roleCode == roleCode }
            .sorted { lhs, rhs in
                let l = phaseOrder[lhs.phase] ?? .max
                let r = phaseOrder[rhs.phase] ?? .max
                if l != r { return l < r }
                return lhs.id < rhs.id
            }
            .prefix(limit)
            .map {
                TaskLineVO(
                    id: $0.id,
                    roleCode: $0.roleCode,
                    phase: $0.phase,
                    text: $0.text.collapsedWhitespace,
                    sourceRef: $0.sourceRef
                )
            }
    }

    private func hubRow(id: String) -> Hub? {
        let descriptor = FetchDescriptor<Hub>(predicate: #Predicate<Hub> { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func kitContents(of hub: Hub) -> [String] {
        guard let data = hub.kitContentsJSON.data(using: .utf8),
              let items = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return items.compactMap { $0.nonEmptyTrimmed }
    }

    // MARK: - Retrieval (prose only)

    struct RetrievalResult: Sendable {
        var passages: [RetrievedPassageVO]
        /// Relevant passages the board view was not allowed to see.
        var withheldPassageCount: Int
        var planProseAvailable: Bool
    }

    /// Candidates are the regional Hub Guide plus **this hub's** plan prose.
    /// No other hub's plan is ever a candidate — the scope is applied when the
    /// candidates are gathered, not when they are ranked (architecture.md §9).
    func retrieve(
        question: String,
        hub: Hub,
        viewLevel: ViewLevel,
        limit: Int = 4
    ) -> RetrievalResult {
        let plan = planChunks.passages(forHubID: hub.id)
        let candidates = guidePassages() + plan

        var allowed = candidates
        var withheldRelevant = 0
        if viewLevel == .public {
            let terms = restrictedTerms(for: hub)
            var blocked: [RetrievedPassageVO] = []
            allowed = candidates.filter { passage in
                if Self.isRestrictedProse(passage.text, restrictedTerms: terms) {
                    blocked.append(passage)
                    return false
                }
                return true
            }
            withheldRelevant = PassageRetriever
                .rank(question: question, candidates: blocked, limit: limit)
                .count
        }

        return RetrievalResult(
            passages: PassageRetriever.rank(question: question, candidates: allowed, limit: limit),
            withheldPassageCount: withheldRelevant,
            planProseAvailable: !plan.isEmpty
        )
    }

    func guidePassages() -> [RetrievedPassageVO] {
        let rows = (try? context.fetch(FetchDescriptor<GuideChunk>())) ?? []
        return rows.map {
            RetrievedPassageVO(
                id: "guide|\($0.section)|\($0.part)",
                origin: .guide,
                hubID: nil,
                section: $0.section,
                text: $0.text.collapsedWhitespace,
                sourceRef: $0.sourceRef
            )
        }
    }

    /// Force-include opening guide sections + this hub's facility map for setup Q&A.
    func augmentForSetup(
        base: RetrievalResult,
        hub: Hub,
        viewLevel: ViewLevel
    ) -> RetrievalResult {
        let setupSections = [
            "Accessing the hub",
            "Working as a team",
            "Setting up",
            "Before you open",
        ]
        var extra = guidePassages().filter { p in
            setupSections.contains { p.section.localizedCaseInsensitiveContains($0) }
        }
        // Prefer early parts of each section
        extra.sort { lhs, rhs in
            if lhs.section != rhs.section { return lhs.section < rhs.section }
            return lhs.id < rhs.id
        }
        // Cap guide bulk but keep multi-section coverage
        var picked: [RetrievedPassageVO] = []
        var perSection: [String: Int] = [:]
        for p in extra {
            let n = perSection[p.section, default: 0]
            guard n < 2 else { continue }
            perSection[p.section] = n + 1
            picked.append(p)
        }

        // Hub facility map / kit / water from plan prose
        let plan = planChunks.passages(forHubID: hub.id).filter { p in
            let s = p.section.lowercased()
            let t = p.text.lowercased()
            return s.contains("facility") || s.contains("map") || s.contains("kit")
                || t.contains("hub kit") || t.contains("emergency water")
                || t.contains("suggested space") || s.contains("coordinate with neighbouring")
        }

        var terms: [String] = []
        if viewLevel == .public {
            terms = restrictedTerms(for: hub)
        }
        let planAllowed = plan.filter { p in
            viewLevel == .coordinator || !Self.isRestrictedProse(p.text, restrictedTerms: terms)
        }

        var merged = base.passages
        for p in picked + planAllowed where !merged.contains(where: { $0.id == p.id }) {
            merged.append(p)
        }
        return RetrievalResult(
            passages: Array(merged.prefix(12)),
            withheldPassageCount: base.withheldPassageCount,
            planProseAvailable: base.planProseAvailable || !planAllowed.isEmpty
        )
    }

    static func isRestrictedProse(_ text: String, restrictedTerms: [String]) -> Bool {
        if RestrictedVocabulary.matches(text) { return true }
        for term in restrictedTerms where text.containsInsensitive(term) {
            return true
        }
        return false
    }
}

/// Category words for the facilities the CRPs are not allowed to expose in board
/// view. Belt-and-braces on top of `hub_asset.sensitivity`: the corpus classifier
/// is pattern based, and a miss here would be a privacy failure rather than a bug.
enum RestrictedVocabulary {
    static let terms: [String] = [
        "rest home",
        "resthome",
        "retirement village",
        "retirement home",
        "retirement complex",
        "aged care",
        "aged residential",
        "care home",
        "nursing home",
        "dementia",
        "hospital level care",
        "hospital-level care",
        "social housing",
        "kainga ora",
        "kāinga ora",
        "council housing",
        "pensioner flat",
        "pensioner housing",
        "supported living",
        "disability residential",
        "womens refuge",
        "women's refuge",
    ]

    static func matches(_ text: String) -> Bool {
        for term in terms where text.containsInsensitive(term) {
            return true
        }
        return false
    }
}
