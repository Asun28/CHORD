import Foundation

/// Tries OpenAI-compatible local endpoint; falls back to deterministic offline client.
/// Board always works with the model off (architecture.md §2).
@MainActor
final class CompositeInferenceClient: InferenceClient, AskInferenceClient {
    private let offline = OfflineInferenceClient()
    private let config: NodeConfig
    private var remote: OpenAICompatibleClient?

    /// True when the most recent successful remote call actually used the model.
    private(set) var lastAnswerCameFromModel = false
    /// Last remote error (for Ask UI / Settings).
    private(set) var lastRemoteError: String?

    init(config: NodeConfig = .shared) {
        self.config = config
        rebuildRemote()
    }

    func rebuildRemote() {
        guard config.inferenceEnabled,
              let base = config.baseURL
        else {
            remote = nil
            return
        }
        let model = config.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        remote = OpenAICompatibleClient(config: .init(
            baseURL: base,
            model: model.isEmpty ? "local-model" : model,
            apiKey: config.apiKey
        ))
    }

    var isRemoteConfigured: Bool {
        config.inferenceEnabled && config.baseURL != nil
    }

    func probe() async -> String {
        rebuildRemote()
        guard let remote else {
            return "Offline only — enable inference and set a base URL"
        }
        do {
            let models = try await remote.listModels()
            // Auto-pick a real model if the configured name is a placeholder / missing
            if !models.isEmpty {
                let current = config.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                let placeholder = current.isEmpty
                    || current == "local-model"
                    || !models.contains(current)
                if placeholder {
                    config.modelName = models[0]
                    rebuildRemote()
                    return "Connected · using model “\(models[0])” (from server list: \(models.prefix(5).joined(separator: ", ")))"
                }
            }
            if models.isEmpty {
                return "Connected to \(config.baseURLString) · no models listed — set model name manually"
            }
            return "Connected · models: \(models.prefix(5).joined(separator: ", ")) · using “\(config.modelName)”"
        } catch {
            lastRemoteError = error.localizedDescription
            return "Unreachable: \(error.localizedDescription)"
        }
    }

    // MARK: - InferenceClient

    func summariseSituation(
        drivers: [SituationDriver],
        hubName: String,
        posture: Posture
    ) async throws -> SituationSummary {
        lastAnswerCameFromModel = false
        guard let remote, isRemoteConfigured else {
            return try await offline.summariseSituation(drivers: drivers, hubName: hubName, posture: posture)
        }
        do {
            let driverLines = drivers.map {
                "- [\($0.observationID)] \($0.headline) (age \($0.ageLabel), \($0.trustTier.label), \($0.attribution))"
            }.joined(separator: "\n")
            let system = """
            You are an operations brief writer for a New Zealand Community Emergency Hub.
            Rules:
            - Use ONLY the driver facts provided. Do not invent hazards, roads, or facilities.
            - Cite observation IDs from the list in the citations array.
            - Reply with JSON only (no markdown): {"headline":"...","prose":"...","citations":["id",...]}
            - Keep prose under 80 words, plain language for volunteers.
            """
            let user = """
            Hub: \(hubName)
            Posture (already decided by rules, do not change): \(posture.title)
            Drivers:
            \(driverLines.isEmpty ? "(none)" : driverLines)
            """
            let raw = try await remote.chatJSON(system: system, user: user)
            if let parsed = decode(SituationSummaryDTO.self, from: raw) {
                lastAnswerCameFromModel = true
                lastRemoteError = nil
                return SituationSummary(
                    headline: parsed.headline,
                    prose: parsed.prose,
                    citations: parsed.citations
                )
            }
            // Free-text model output still counts as model-sourced prose
            lastAnswerCameFromModel = true
            lastRemoteError = nil
            return SituationSummary(
                headline: "\(hubName): \(posture.title)",
                prose: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                citations: drivers.prefix(5).map(\.observationID)
            )
        } catch {
            lastRemoteError = error.localizedDescription
            print("HubNode summarise failed: \(error)")
            return try await offline.summariseSituation(drivers: drivers, hubName: hubName, posture: posture)
        }
    }

    func selectTasks(
        posture: Posture,
        rolesPresent: [String],
        templates: [TaskTemplateDTO]
    ) async throws -> [SelectedTask] {
        guard let remote, isRemoteConfigured else {
            return try await offline.selectTasks(posture: posture, rolesPresent: rolesPresent, templates: templates)
        }
        do {
            let catalogue = templates.prefix(40).map {
                "{\"id\":\"\($0.id)\",\"role\":\"\($0.roleCode)\",\"phase\":\"\($0.phase)\",\"text\":\(jsonString($0.text))}"
            }.joined(separator: ",\n")
            let system = """
            You select emergency hub tasks from a fixed catalogue. You NEVER invent task text.
            Reply with JSON only: {"tasks":[{"template_id":"...","assignee_role":"...","order":0,"reason":"..."}]}
            Only use template_id values from the catalogue. Prefer priority roles and current posture phases.
            Max 3 tasks per role present.
            """
            let user = """
            Posture: \(posture.rawValue)
            Roles present: \(rolesPresent.joined(separator: ", "))
            Catalogue: [\(catalogue)]
            """
            let raw = try await remote.chatJSON(system: system, user: user)
            if let parsed = decode(SelectedTasksDTO.self, from: raw) {
                let allowed = Set(templates.map(\.id))
                let filtered = parsed.tasks.compactMap { t -> SelectedTask? in
                    guard allowed.contains(t.template_id) else { return nil }
                    return SelectedTask(
                        templateID: t.template_id,
                        assigneeRole: t.assignee_role,
                        order: t.order,
                        reason: t.reason
                    )
                }
                if !filtered.isEmpty {
                    lastRemoteError = nil
                    return filtered
                }
            }
            return try await offline.selectTasks(posture: posture, rolesPresent: rolesPresent, templates: templates)
        } catch {
            lastRemoteError = error.localizedDescription
            return try await offline.selectTasks(posture: posture, rolesPresent: rolesPresent, templates: templates)
        }
    }

    func suggestRole(
        answers: [String: String],
        unfilledPriorityRoles: [String]
    ) async throws -> RoleSuggestion {
        guard let remote, isRemoteConfigured else {
            return try await offline.suggestRole(answers: answers, unfilledPriorityRoles: unfilledPriorityRoles)
        }
        do {
            let system = """
            You assign one of eight WREMO hub roles. Reply with JSON only:
            {"role_code":"...","rationale":"...","second_choice":"..."}
            Prefer unfilled priority roles when the answers fit. role_code must be one of:
            hub_supervisor, information_coord, public_information, reception,
            needs_and_offers, community_space, communications, facility_maintenance
            """
            let user = """
            Unfilled priority roles: \(unfilledPriorityRoles.joined(separator: ", "))
            Answers: \(answers.map { "\($0.key): \($0.value)" }.joined(separator: "; "))
            """
            let raw = try await remote.chatJSON(system: system, user: user)
            if let parsed = decode(RoleSuggestionDTO.self, from: raw) {
                let allowed: Set<String> = [
                    "hub_supervisor", "information_coord", "public_information", "reception",
                    "needs_and_offers", "community_space", "communications", "facility_maintenance",
                ]
                if allowed.contains(parsed.role_code) {
                    lastRemoteError = nil
                    return RoleSuggestion(
                        roleCode: parsed.role_code,
                        rationale: parsed.rationale,
                        secondChoice: parsed.second_choice.flatMap { allowed.contains($0) ? $0 : nil }
                    )
                }
            }
            return try await offline.suggestRole(answers: answers, unfilledPriorityRoles: unfilledPriorityRoles)
        } catch {
            lastRemoteError = error.localizedDescription
            return try await offline.suggestRole(answers: answers, unfilledPriorityRoles: unfilledPriorityRoles)
        }
    }

    func answerQuestion(
        question: String,
        chunks: [String],
        hubName: String
    ) async throws -> Answer {
        lastAnswerCameFromModel = false
        guard let remote, isRemoteConfigured else {
            lastRemoteError = "Remote not configured"
            return try await offline.answerQuestion(question: question, chunks: chunks, hubName: hubName)
        }
        do {
            let system = """
            You are the live playbook for ONE Community Emergency Hub in New Zealand.
            Volunteers are standing in the hall with you. YOU answer — you do not send them away to a PDF.

            Hard rules:
            - Answer using ONLY the context pack. Prefer SETUP / OPENING STEPS and AVAILABLE ASSETS.
            - Give a numbered checklist of what to do *here*, at this hub, now.
            - Weave in hub-specific facts (address, water tank, kit, neighbours) from the pack.
            - FORBIDDEN phrases: "check the CRP", "check the PDF", "see the plan at https", \
            "follow standard procedures", "refer to the Community Response Plan document", \
            "no specific setup tasks". If SETUP / OPENING STEPS is present, those ARE the tasks.
            - Plan URLs in context are citations only — never step 1 of the answer.
            - If AVAILABLE ASSETS is non-empty, list relevant items; never claim none are listed.
            - Contingency headings like "if facilities are not available" are not asset inventories.
            - Short, plain language for stressed volunteers.
            - Prefer JSON: {"answer":"...","citations":["..."],"unknowns":["..."]}
            - Or plain text if JSON fails. Do not invent hazards or facilities.
            """
            let user = """
            You are on duty at: \(hubName)
            Volunteer asks: \(question)

            Context pack (this is your only source of truth):
            \(chunks.joined(separator: "\n\n---\n\n"))
            """
            let raw = try await remote.chatJSON(system: system, user: user)
            let prose = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prose.isEmpty else {
                throw InferenceError.emptyContent
            }

            if let parsed = decode(AnswerDTO.self, from: prose) {
                lastAnswerCameFromModel = true
                lastRemoteError = nil
                print("HubNode: model answer (JSON) \(parsed.answer.prefix(120))…")
                return Answer(
                    answer: parsed.answer,
                    citations: parsed.citations ?? [],
                    unknowns: parsed.unknowns ?? []
                )
            }

            // Free-text response from the model — still use it as the answer.
            lastAnswerCameFromModel = true
            lastRemoteError = nil
            print("HubNode: model answer (free text) \(prose.prefix(120))…")
            return Answer(
                answer: prose,
                citations: ["Local model · \(hubName)"],
                unknowns: []
            )
        } catch {
            lastRemoteError = error.localizedDescription
            print("HubNode answerQuestion failed: \(error)")
            // Propagate failure info via offline answer + unknowns is handled by AskService
            // when lastAnswerCameFromModel is false — return offline grounded fallback.
            return try await offline.answerQuestion(question: question, chunks: chunks, hubName: hubName)
        }
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        let candidates = [raw, extractJSON(raw)].compactMap { $0 }
        for c in candidates {
            if let data = c.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(T.self, from: data) {
                return parsed
            }
        }
        return nil
    }

    private func extractJSON(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.first == "{" { return t }
        if let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") {
            return String(t[start...end])
        }
        return nil
    }

    private func jsonString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: s)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}

// MARK: - DTOs

private struct SituationSummaryDTO: Decodable {
    var headline: String
    var prose: String
    var citations: [String]
}

private struct SelectedTasksDTO: Decodable {
    struct Task: Decodable {
        var template_id: String
        var assignee_role: String
        var order: Int
        var reason: String
    }
    var tasks: [Task]
}

private struct RoleSuggestionDTO: Decodable {
    var role_code: String
    var rationale: String
    var second_choice: String?
}

private struct AnswerDTO: Decodable {
    var answer: String
    var citations: [String]?
    var unknowns: [String]?

    // Tolerate slightly different keys from smaller models
    enum CodingKeys: String, CodingKey {
        case answer, citations, unknowns
        case response, text, message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let a = try c.decodeIfPresent(String.self, forKey: .answer) {
            answer = a
        } else if let a = try c.decodeIfPresent(String.self, forKey: .response) {
            answer = a
        } else if let a = try c.decodeIfPresent(String.self, forKey: .text) {
            answer = a
        } else if let a = try c.decodeIfPresent(String.self, forKey: .message) {
            answer = a
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.answer,
                .init(codingPath: c.codingPath, debugDescription: "No answer field")
            )
        }
        citations = try c.decodeIfPresent([String].self, forKey: .citations) ?? []
        unknowns = try c.decodeIfPresent([String].self, forKey: .unknowns) ?? []
    }
}
