import Foundation
import Combine

// MARK: - Flow: node identity
/// Persisted hall identity (home hub) + OpenAI-compatible inference endpoint.
/// One Mac Mini / laptop serves one Community Emergency Hub.
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
 static let httpEnabled = "hubnode.httpEnabled"
 static let httpPort = "hubnode.httpPort"
 static let httpLAN = "hubnode.httpLAN"
 }

 @Published var homeHubID: String? {
 didSet { UserDefaults.standard.set(homeHubID, forKey: Keys.homeHubID) }
 }

 /// When false, always use OfflineInferenceClient.
 @Published var inferenceEnabled: Bool {
 didSet { UserDefaults.standard.set(inferenceEnabled, forKey: Keys.inferenceEnabled) }
 }

 /// e.g. http://127.0.0.1:1234/v1 (LM Studio) or http://127.0.0.1:11434/v1 (Ollama)
 @Published var baseURLString: String {
 didSet { UserDefaults.standard.set(baseURLString, forKey: Keys.baseURL) }
 }

 @Published var modelName: String {
 didSet { UserDefaults.standard.set(modelName, forKey: Keys.model) }
 }

 /// Optional. Most local servers ignore this; keep empty unless needed.
 @Published var apiKey: String {
 didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
 }

 @Published var setupComplete: Bool {
 didSet { UserDefaults.standard.set(setupComplete, forKey: Keys.setupComplete) }
 }

 /// Last connectivity probe result for Settings UI.
 @Published var lastProbeMessage: String = ""

 /// Embed Companion web board + REST API in this process.
 @Published var httpServerEnabled: Bool {
  didSet { UserDefaults.standard.set(httpServerEnabled, forKey: Keys.httpEnabled) }
 }

 @Published var httpPort: Int {
  didSet { UserDefaults.standard.set(httpPort, forKey: Keys.httpPort) }
 }

 /// When true, bind beyond loopback so hall phones can join (opt-in).
 @Published var httpLANEnabled: Bool {
  didSet { UserDefaults.standard.set(httpLANEnabled, forKey: Keys.httpLAN) }
 }

 @Published var httpStatusMessage: String = ""

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
 // Prefer Ollama's OpenAI-compatible port by default; LM Studio is a Settings preset.
 baseURLString = d.string(forKey: Keys.baseURL) ?? "http://127.0.0.1:11434/v1"
 // Placeholder until ensureRemoteReady() / Test connection picks a real id from the server.
 modelName = d.string(forKey: Keys.model) ?? "local-model"
 apiKey = d.string(forKey: Keys.apiKey) ?? ""
 setupComplete = d.bool(forKey: Keys.setupComplete)
 if d.object(forKey: Keys.httpEnabled) == nil {
  httpServerEnabled = true
 } else {
  httpServerEnabled = d.bool(forKey: Keys.httpEnabled)
 }
 let port = d.integer(forKey: Keys.httpPort)
 httpPort = (port > 0 && port < 65536) ? port : 8787
 httpLANEnabled = d.bool(forKey: Keys.httpLAN)
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
