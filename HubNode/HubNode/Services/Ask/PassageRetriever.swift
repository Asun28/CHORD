import Foundation

/// Deterministic keyword ranking over a *pre-scoped* candidate set.
///
/// It takes candidates rather than fetching them, which is the point: the caller
/// (HubFactStore) has already applied the hub scope and the privacy gate, so the
/// retriever cannot widen either. No embeddings — a hall laptop with no model
/// still has to rank, and the demo has to be reproducible.
enum PassageRetriever {
    /// Section-title hits weigh more than body hits: WREMO's plans use
    /// question-shaped headings, so a volunteer's wording often lands on one.
    static let sectionWeight: Double = 3.0
    static let planWeight: Double = 1.15

    static func rank(
        question: String,
        candidates: [RetrievedPassageVO],
        limit: Int = 4
    ) -> [RetrievedPassageVO] {
        let terms = Set(question.askTokens)
        guard !terms.isEmpty else { return [] }

        var scored: [RetrievedPassageVO] = []
        scored.reserveCapacity(candidates.count)
        for candidate in candidates {
            let score = score(terms: terms, candidate: candidate)
            guard score > 0 else { continue }
            var hit = candidate
            hit.score = score
            scored.append(hit)
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.id < rhs.id  // stable order for identical scores
            }
            .prefix(limit)
            .map { $0 }
    }

    static func score(terms: Set<String>, candidate: RetrievedPassageVO) -> Double {
        let bodyTokens = candidate.text.askTokens
        guard !bodyTokens.isEmpty else { return 0 }
        let sectionTokens = Set(candidate.section.askTokens)

        var matched: Set<String> = []
        var hits = 0
        for token in bodyTokens where terms.contains(token) {
            hits += 1
            matched.insert(token)
        }
        var score = Double(hits) / (Double(bodyTokens.count).squareRootForRanking)
        score += Double(terms.intersection(sectionTokens).count) * sectionWeight
        guard score > 0 else { return 0 }

        // Coverage bonus: a passage touching three of the asked terms beats one
        // that repeats a single term ten times.
        score *= 1.0 + Double(matched.count) / Double(terms.count)
        if candidate.origin == .hubPlan { score *= planWeight }
        return score
    }
}

private extension Double {
    /// Length normalisation. Named rather than inlined so the ranking formula
    /// reads as one line.
    var squareRootForRanking: Double {
        self <= 1 ? 1 : squareRoot()
    }
}
