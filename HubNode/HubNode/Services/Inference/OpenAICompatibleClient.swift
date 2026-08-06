import Foundation

// MARK: - Flow: HTTP to local model
/// OpenAI-compatible chat (LM Studio / Ollama). Language only — never posture.
/// Retries without `response_format` when the server 400s (common on Ollama).
actor OpenAICompatibleClient {
    struct Config: Sendable {
        var baseURL: URL
        var model: String
        var apiKey: String
        var timeout: TimeInterval

        init(baseURL: URL, model: String, apiKey: String = "", timeout: TimeInterval = 120) {
            self.baseURL = baseURL
            self.model = model
            self.apiKey = apiKey
            self.timeout = timeout
        }
    }

    private var config: Config
    private let session: URLSession

    init(config: Config) {
        self.config = config
        let conf = URLSessionConfiguration.default
        conf.timeoutIntervalForRequest = config.timeout
        conf.timeoutIntervalForResource = config.timeout
        conf.waitsForConnectivity = false
        self.session = URLSession(configuration: conf)
    }

    func updateConfig(_ config: Config) {
        self.config = config
    }

    func currentModel() -> String { config.model }

    // MARK: - Chat

    /// Prefer JSON; if the server rejects `response_format` (common on Ollama), retry plain chat.
    func chatJSON(
        system: String,
        user: String,
        temperature: Double = 0.2
    ) async throws -> String {
        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ]
        do {
            return try await complete(messages: messages, temperature: temperature, jsonMode: true)
        } catch {
            // Ollama often 400s on response_format — fall through without it.
            print("HubNode: chatJSON with response_format failed (\(error)) — retrying plain")
            return try await complete(messages: messages, temperature: temperature, jsonMode: false)
        }
    }

    /// Plain chat (no JSON mode flag). Still asks for JSON in the system prompt.
    func chat(
        system: String,
        user: String,
        temperature: Double = 0.2
    ) async throws -> String {
        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ]
        return try await complete(messages: messages, temperature: temperature, jsonMode: false)
    }

    func complete(
        messages: [[String: String]],
        temperature: Double,
        jsonMode: Bool
    ) async throws -> String {
        let url = try endpoint("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": temperature,
            "stream": false,
        ]
        // Many Ollama builds reject this — callers that need JSON should use chatJSON (retries).
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        print("HubNode: POST \(url.absoluteString) model=\(config.model) jsonMode=\(jsonMode)")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InferenceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            print("HubNode: inference HTTP \(http.statusCode): \(snippet.prefix(500))")
            throw InferenceError.httpStatus(http.statusCode, String(snippet.prefix(400)))
        }

        // Ollama/OpenAI shape
        if let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
           let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return extractJSONObject(from: content) ?? content
        }

        // Some servers put text at the root
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = obj["response"] as? String,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return extractJSONObject(from: t) ?? t
        }

        let raw = String(data: data, encoding: .utf8) ?? ""
        print("HubNode: could not parse completion: \(raw.prefix(400))")
        throw InferenceError.emptyContent
    }

    /// GET /models — connectivity probe + model discovery.
    func listModels() async throws -> [String] {
        let url = try endpoint("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InferenceError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1, "")
        }
        if let obj = try? JSONDecoder().decode(ModelsListResponse.self, from: data) {
            return obj.data.map(\.id)
        }
        return []
    }

    // MARK: - URL helpers

    /// Join base (…/v1 or …/v1/) with a relative path without dropping `/v1`.
    private func endpoint(_ path: String) throws -> URL {
        var base = config.baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: base + "/" + rel) else {
            throw InferenceError.notConfigured
        }
        return url
    }

    /// Models sometimes wrap JSON in markdown fences; pull the object out.
    private func extractJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            // ```json ... ```
            var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.hasPrefix("```") == true { lines.removeLast() }
            let inner = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.first == "{" { return inner }
        }
        if trimmed.first == "{" { return trimmed }
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return nil
    }
}

// MARK: - Wire types

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var role: String?
            var content: String?
        }
        var message: Message
        var text: String? // rare alternate
    }
    var choices: [Choice]
}

private struct ModelsListResponse: Decodable {
    struct Model: Decodable { var id: String }
    var data: [Model]
}

enum InferenceError: Error, LocalizedError {
    case invalidResponse
    case emptyContent
    case httpStatus(Int, String)
    case notConfigured
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from inference server"
        case .emptyContent: return "Model returned empty content"
        case .httpStatus(let code, let body): return "HTTP \(code): \(body)"
        case .notConfigured: return "Inference endpoint not configured"
        case .decodeFailed(let m): return "Could not parse model JSON: \(m)"
        }
    }
}
