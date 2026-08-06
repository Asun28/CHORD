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

 Section("Local model (LM Studio / Ollama)") {
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

 Text("OpenAI-compatible `/v1/chat/completions`. Board still works if the model is offline.")
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
 }

 Section("Attribution") {
 Text(CorpusBootstrap.attribution)
 .font(.caption)
 }
 }
 .formStyle(.grouped)
 .padding()
 .frame(minWidth: 440, minHeight: 520)
 }
}
