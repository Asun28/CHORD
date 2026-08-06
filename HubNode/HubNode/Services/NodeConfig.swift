import Foundation
import Combine

/// Persistent node identity + inference endpoint.
/// This machine sits in *one* Community Emergency Hub hall.
@MainActor
final class NodeConfig: ObservableObject {
    static let shared = NodeConfig()

    private enum Keys {
        static let homeHubID = "hubnode.homeHubID"
        static let inferenceEnabled = "hubnode.inferenceEnabled"
        static let baseURL = "hubnode.inferenceBaseURL"
        static let model = "hubnode.inferenceModel"
        static let apiKey = "hubnode.inferenceAPIKey"
        static let setupComplete = "hubnode.setupComplete"
    }

    @Published var homeHubID: String? {
        didSet { UserDefaults.standard.set(homeHubID, forKey: Keys.homeHubID) }
    }

    /// When false, always use OfflineInferenceClient.
    @Published var inferenceEnabled: Bool {
        didSet { UserDefaults.standard.set(inferenceEnabled, forKey: Keys.inferenceEnabled) }
    }

    /// e.g. http://127.0.0.1:1234/v1  (LM Studio) or http://127.0.0.1:11434/v1 (Ollama)
    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Keys.baseURL) }
    }

    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: Keys.model) }
    }

    /// Optional — most local servers ignore this; keep empty unless needed.
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }

    @Published var setupComplete: Bool {
        didSet { UserDefaults.standard.set(setupComplete, forKey: Keys.setupComplete) }
    }

    /// Last connectivity probe result for Settings UI.
    @Published var lastProbeMessage: String = ""

    var baseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Accept with or without trailing /v1
        return URL(string: trimmed)
    }

    var needsSetup: Bool {
        !setupComplete || homeHubID == nil || homeHubID?.isEmpty == true
    }

    init() {
        let d = UserDefaults.standard
        homeHubID = d.string(forKey: Keys.homeHubID)
        // Default ON so plugging in LM Studio just works once URL is set
        if d.object(forKey: Keys.inferenceEnabled) == nil {
            inferenceEnabled = true
        } else {
            inferenceEnabled = d.bool(forKey: Keys.inferenceEnabled)
        }
        baseURLString = d.string(forKey: Keys.baseURL) ?? "http://127.0.0.1:1234/v1"
        modelName = d.string(forKey: Keys.model) ?? "local-model"
        apiKey = d.string(forKey: Keys.apiKey) ?? ""
        setupComplete = d.bool(forKey: Keys.setupComplete)
    }

    func setHomeHub(id: String) {
        homeHubID = id
        setupComplete = true
    }

    func clearHomeHub() {
        homeHubID = nil
        setupComplete = false
    }

    /// Presets for the settings UI.
    static let presets: [(name: String, url: String)] = [
        ("LM Studio", "http://127.0.0.1:1234/v1"),
        ("Ollama", "http://127.0.0.1:11434/v1"),
        ("Custom", "http://127.0.0.1:8000/v1"),
    ]
}
