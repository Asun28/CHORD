import Foundation

public struct SituationSummary: Codable, Sendable {
    public var headline: String
    public var prose: String
    public var citations: [String]
}

public struct SelectedTask: Codable, Sendable, Identifiable {
    public var id: String { templateID }
    public var templateID: String
    public var assigneeRole: String
    public var order: Int
    public var reason: String
}

public struct RoleSuggestion: Codable, Sendable {
    public var roleCode: String
    public var rationale: String
    public var secondChoice: String?
}

public struct Answer: Codable, Sendable {
    public var answer: String
    public var citations: [String]
    public var unknowns: [String]
}

public protocol InferenceClient: Sendable {
    func summariseSituation(
        drivers: [SituationDriver],
        hubName: String,
        posture: Posture
    ) async throws -> SituationSummary

    func selectTasks(
        posture: Posture,
        rolesPresent: [String],
        templates: [TaskTemplateDTO]
    ) async throws -> [SelectedTask]

    func suggestRole(
        answers: [String: String],
        unfilledPriorityRoles: [String]
    ) async throws -> RoleSuggestion

    func answerQuestion(
        question: String,
        chunks: [String],
        hubName: String
    ) async throws -> Answer
}

public struct TaskTemplateDTO: Sendable, Identifiable {
    public var id: String
    public var roleCode: String
    public var phase: String
    public var text: String
    public var sourceRef: String

    public init(id: String, roleCode: String, phase: String, text: String, sourceRef: String) {
        self.id = id
        self.roleCode = roleCode
        self.phase = phase
        self.text = text
        self.sourceRef = sourceRef
    }
}

/// Deterministic offline client — board stays functional with inference off.
public struct OfflineInferenceClient: InferenceClient {
    public init() {}

    public func summariseSituation(
        drivers: [SituationDriver],
        hubName: String,
        posture: Posture
    ) async throws -> SituationSummary {
        if drivers.isEmpty {
            return SituationSummary(
                headline: "\(hubName): quiet",
                prose: "No active hazards currently match this hub. Keep the board honest as feeds age.",
                citations: []
            )
        }
        let top = drivers.prefix(3).map(\.headline).joined(separator: "; ")
        return SituationSummary(
            headline: "\(hubName): \(posture.title)",
            prose: "Situation is \(posture.title.lowercased()). Key drivers: \(top).",
            citations: drivers.prefix(5).map(\.observationID)
        )
    }

    public func selectTasks(
        posture: Posture,
        rolesPresent: [String],
        templates: [TaskTemplateDTO]
    ) async throws -> [SelectedTask] {
        let phases: [String]
        switch posture {
        case .green: phases = ["access", "team", "setup"]
        case .watch: phases = ["team", "setup", "before_open"]
        case .act: phases = ["before_open", "response", "team"]
        case .respond: phases = ["response", "access", "team"]
        }
        var selected: [SelectedTask] = []
        var order = 0
        for role in rolesPresent {
            let matches = templates.filter { $0.roleCode == role && phases.contains($0.phase) }
            let fallback = templates.filter { $0.roleCode == role }
            let pick = Array((matches.isEmpty ? fallback : matches).prefix(3))
            for t in pick {
                selected.append(SelectedTask(
                    templateID: t.id,
                    assigneeRole: role,
                    order: order,
                    reason: "Catalogue default for \(posture.title) / \(t.phase)"
                ))
                order += 1
            }
        }
        return selected
    }

    public func suggestRole(
        answers: [String: String],
        unfilledPriorityRoles: [String]
    ) async throws -> RoleSuggestion {
        // Prefer unfilled priority roles; simple keyword heuristic on answers
        let blob = answers.values.joined(separator: " ").lowercased()
        let keywordMap: [(String, String)] = [
            ("radio", "communications"),
            ("people", "reception"),
            ("welcome", "reception"),
            ("write", "public_information"),
            ("board", "information_coord"),
            ("organise", "hub_supervisor"),
            ("lead", "hub_supervisor"),
            ("fix", "facility_maintenance"),
            ("match", "needs_and_offers"),
            ("care", "community_space"),
        ]
        var scored: [String: Int] = [:]
        for (kw, role) in keywordMap {
            if blob.contains(kw) { scored[role, default: 0] += 2 }
        }
        for role in unfilledPriorityRoles {
            scored[role, default: 0] += 3
        }
        let ranked = scored.sorted { $0.value > $1.value }.map(\.key)
        let primary = ranked.first
            ?? unfilledPriorityRoles.first
            ?? "reception"
        let second = ranked.dropFirst().first
            ?? unfilledPriorityRoles.dropFirst().first
        return RoleSuggestion(
            roleCode: primary,
            rationale: unfilledPriorityRoles.contains(primary)
                ? "Priority role still unfilled; matches what you said you can do."
                : "Best fit from your answers among remaining roles.",
            secondChoice: second
        )
    }

    public func answerQuestion(
        question: String,
        chunks: [String],
        hubName: String
    ) async throws -> Answer {
        let snippet = chunks.first.map { String($0.prefix(400)) } ?? ""
        if snippet.isEmpty {
            return Answer(
                answer: "I don't have guide text loaded for that yet.",
                citations: [],
                unknowns: ["No matching guide chunk"]
            )
        }
        return Answer(
            answer: "From the Hub Guide for \(hubName):\n\n\(snippet)",
            citations: ["WREMO Hub Guide"],
            unknowns: []
        )
    }
}
