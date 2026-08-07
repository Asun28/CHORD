import SwiftUI

struct SettingsView: View {
 @EnvironmentObject private var app: AppModel
 @ObservedObject private var config = NodeConfig.shared

 var body: some View {
 Form {
 Section("This hub") {
 if let home = app.homeMapHub {
 LabeledContent("Home hub", value: home.name)
 LabeledContent("Area", value: home.taName)
 LabeledContent("Address", value: home.address)
 } else {
 Text("No home hub set")
 .foregroundStyle(.orange)
 }
 Button("Change home hub…") {
 app.changeHomeHub()
 }
 }

 Section("Kea / Ask agent (local model)") {
 Text("Single agent for the Mac board and the web Companion. Configure only here. Browsers call the same AskService path and cannot pick a different model.")
  .font(.caption)
  .foregroundStyle(.secondary)

 Toggle("Use local inference", isOn: $config.inferenceEnabled)
 .onChange(of: config.inferenceEnabled) { _, _ in
 app.rebuildInference()
 }

 Picker("Preset", selection: $config.baseURLString) {
 ForEach(NodeConfig.presets, id: \.url) { preset in
 Text(preset.name).tag(preset.url)
 }
 }
 .onChange(of: config.baseURLString) { _, _ in
 app.rebuildInference()
 }

 TextField("Base URL", text: $config.baseURLString)
 .textFieldStyle(.roundedBorder)
 .onSubmit { app.rebuildInference() }

 TextField("Model name", text: $config.modelName)
 .textFieldStyle(.roundedBorder)
 .onSubmit { app.rebuildInference() }

 SecureField("API key (optional)", text: $config.apiKey)
 .textFieldStyle(.roundedBorder)

 Button("Test connection") {
 Task { await app.probeInference() }
 }
 if !config.lastProbeMessage.isEmpty {
 Text(config.lastProbeMessage)
 .font(.caption)
 .foregroundStyle(.secondary)
 .textSelection(.enabled)
 }

 Text("OpenAI-compatible `/v1/chat/completions` (LM Studio / Ollama). Web Ask Kea uses this endpoint. Board still works if the model is offline (grounded corpus floor).")
 .font(.caption)
 .foregroundStyle(.secondary)
 }

 Section("Coordinator") {
 Text("Kit unlock code: \(AppModel.coordinatorCode)")
 .font(.body.monospaced())
 }

 Section("Corpus") {
 Text("Map hubs: \(app.mapHubs.count)")
 Text("Plan prose hubs: \(PlanChunkStore.shared.hubCount)")
 .foregroundStyle(.secondary)
 if let err = app.lastError {
 Text(err)
 .font(.caption)
 .foregroundStyle(.orange)
 }
 Button("Reload corpus") {
 Task { await app.reloadCorpus() }
 }
 }

 Section("Demo") {
 Toggle("Replay mode (fixtures)", isOn: $app.isReplayMode)
 Toggle("Use Companion demo scenario", isOn: $config.demoScenarioEnabled)
 Text(
  "When on, Kea status answers use the Companion seed monitor (M7.1, aftershocks, sit board). When off, Ask only sees live or fixture CAP drivers."
 )
  .font(.caption)
  .foregroundStyle(.secondary)
 if config.demoScenarioEnabled {
  Text(CompanionSeedStore.shared.loadMessage)
   .font(.caption2)
   .foregroundStyle(.secondary)
 }
 }

 Section("Web board (Companion)") {
 Toggle("Host board over HTTP", isOn: $config.httpServerEnabled)
  .onChange(of: config.httpServerEnabled) { _, _ in
   app.syncHTTPServer()
  }
 TextField("Port", value: $config.httpPort, format: .number)
  .textFieldStyle(.roundedBorder)
  .onSubmit { app.syncHTTPServer() }
 Toggle("Allow hall LAN (not just this Mac)", isOn: $config.httpLANEnabled)
  .onChange(of: config.httpLANEnabled) { _, _ in
   app.syncHTTPServer()
  }
 if !config.httpStatusMessage.isEmpty {
  Text(config.httpStatusMessage)
   .font(.caption)
   .foregroundStyle(.secondary)
   .textSelection(.enabled)
 }
 Button("Open board in browser") {
  app.openHTTPBoardInBrowser()
 }
 Button("Restart web server") {
  app.syncHTTPServer()
 }
 Text("Live board at / (My shift, Situation, Needs, Roster, Monitor, Public, Ask Kea) · /console for full offline demo · API under /api/v1. Kea model is set only in the section above.")
  .font(.caption)
  .foregroundStyle(.secondary)
 Text(CompanionSeedStore.shared.loadMessage)
  .font(.caption2)
  .foregroundStyle(.secondary)
 }

 Section("Attribution") {
 Text(CorpusBootstrap.attribution)
 .font(.caption)
 }
 }
 .formStyle(.grouped)
 .padding()
 .frame(minWidth: 440, minHeight: 640)
 }
}
