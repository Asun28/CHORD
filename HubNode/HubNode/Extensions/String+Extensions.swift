import Foundation

// MARK: - Ask retrieval helpers

extension String {
    /// Stopwords stripped before scoring. Kept small and explicit — retrieval has
    /// to be reproducible on stage, so there is no stemmer and no embedding model.
    static let askStopwords: Set<String> = [
        "the", "and", "for", "are", "our", "you", "your", "with", "that", "this",
        "what", "when", "where", "who", "whom", "how", "why", "does", "did", "was",
        "were", "will", "would", "should", "could", "can", "has", "have", "had",
        "any", "all", "not", "but", "from", "into", "out", "off", "its", "his",
        "her", "they", "them", "there", "here", "about", "need", "needs", "get",
        "got", "use", "used", "hub", "hubs",
    ]

    /// Lowercased alphanumeric tokens with stopwords removed.
    var askTokens: [String] {
        let mapped = unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped)
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !String.askStopwords.contains($0) }
    }

    /// Diacritic- and case-insensitive containment. Restricted asset names come
    /// out of PDF text with inconsistent macrons, so matching has to be forgiving.
    func containsInsensitive(_ other: String) -> Bool {
        guard !other.isEmpty else { return false }
        return range(of: other, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var collapsedWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func truncated(to limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    var nonEmptyTrimmed: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Optional string helpers

extension Optional where Wrapped == String {
    /// `hub.crpReviewedOn.nonEmptyTrimmed` — flattens what `?.nonEmptyTrimmed`
    /// would otherwise hand back as `String??`, which silently interpolates as
    /// `Optional("2025-06")` on screen.
    var nonEmptyTrimmed: String? {
        flatMap { $0.nonEmptyTrimmed }
    }
}
