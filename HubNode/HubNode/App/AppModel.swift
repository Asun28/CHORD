import Foundation
import SwiftData
import SwiftUI
import Combine
import MapKit

// MARK: - Flow: app lifecycle
/// Owns the hall node: home hub identity, corpus map pins, feed poll → posture,
/// door flow, and Ask. UI reads published state; services mutate SwiftData on mainContext.
///
/// Bootstrap order: load map hubs (JSON) → apply home hub → seed SwiftData if needed
/// → poll fixtures/feeds → recompute situations. Model is never on the posture path.

@MainActor
final class AppModel: ObservableObject {
 let container: ModelContainer
 var context: ModelContext { container.mainContext }

 let nodeConfig = NodeConfig.shared
 private(set) var inferenceClient: CompositeInferenceClient
 private(set) var askService: AskService!

 /// Direct map source. Value types from corpus JSON.
 @Published var mapHubs: [HubMapItem] = []
 /// Currently viewed hub (may differ from home when browsing region).
 @Published var selectedHubID: String?
 @Published var cursor: Date = DemoReplay.timelineStart
 @Published var isReplayMode: Bool = true
 @Published var situations: [String: SituationSnapshot] = [:]
 @Published var coordinatorUnlocked: Bool = false
 @Published var statusMessage: String = "Starting…"
 @Published var isBusy: Bool = false
 @Published var showStalenessMode: Bool = false
 @Published var corpusGeneration: Int = 0
 @Published var lastError: String?
 @Published var showHomeSetup: Bool = false
 @Published var showRegionalMap: Bool = false

 private(set) var pollLoop: PollLoop!
 private(set) var situationService: SituationService!
 private(set) var doorFlow: DoorFlowService!

 /// Back-compat for call sites that use `app.inference`.
 var inference: any InferenceClient { inferenceClient }

 private var didBootstrap = false
 static let coordinatorCode = "HUBKIT"

 static let wellingtonRegion = MKCoordinateRegion(
 center: CLLocationCoordinate2D(latitude: -41.15, longitude: 175.05),
 span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.8)
 )

 init(inMemory: Bool = false) {
 let schema = Schema([
 Hub.self,
 HubAsset.self,
 RoleDef.self,
 TaskTemplate.self,
 GuideChunk.self,
 ObservationRecord.self,
 SituationRecord.self,
 HubSession.self,
 Assignment.self,
 SessionTask.self,
 FeedSourceState.self,
 ])
 let config = ModelConfiguration(
 "HubNode",
 schema: schema,
 isStoredInMemoryOnly: inMemory
 )
 do {
 container = try ModelContainer(for: schema, configurations: [config])
 } catch {
 fatalError("Failed to create ModelContainer: \(error)")
 }

 inferenceClient = CompositeInferenceClient(config: NodeConfig.shared)
 pollLoop = PollLoop(context: container.mainContext)
 situationService = SituationService(context: container.mainContext)
 doorFlow = DoorFlowService(context: container.mainContext, inference: inferenceClient)
 askService = AskService(context: container.mainContext, inference: inferenceClient)

 loadMapHubsFromDisk()
 applyHomeHubSelection()
 showHomeSetup = nodeConfig.needsSetup
 }

 // MARK: - Home hub

 var homeHubID: String? { nodeConfig.homeHubID }

 var homeMapHub: HubMapItem? {
 guard let id = homeHubID else { return nil }
 return mapHubs.first { $0.id == id }
 }

 var isViewingHomeHub: Bool {
 selectedHubID != nil && selectedHubID == homeHubID
 }

 func applyHomeHubSelection() {
 if let home = homeHubID, mapHubs.contains(where: { $0.id == home }) {
 selectedHubID = home
 }
 }

 func setHomeHub(id: String) {
 nodeConfig.setHomeHub(id: id)
 selectedHubID = id
 showHomeSetup = false
 showRegionalMap = false
 statusMessage = "Home hub: \(mapHub(id: id)?.name ?? id)"
 // Focus situation refresh for home (full recompute still fine at this scale)
 Task { await refreshFromFeeds() }
 }

 func changeHomeHub() {
 showHomeSetup = true
 }

 // MARK: - Corpus

 @discardableResult
 func loadMapHubsFromDisk() -> Bool {
 do {
 let items = try CorpusBootstrap.loadMapItems()
 mapHubs = items
 corpusGeneration += 1
 lastError = nil
 statusMessage = "Map: \(items.count) hubs from corpus"
 print("HubNode: loaded \(items.count) map hubs")
 return true
 } catch {
 mapHubs = []
 lastError = error.localizedDescription
 statusMessage = "Map load failed: \(error.localizedDescription)"
 print("HubNode: map load failed: \(error)")
 return false
 }
 }

 func bootstrapIfNeeded() async {
 if mapHubs.isEmpty {
 _ = loadMapHubsFromDisk()
 }
 applyHomeHubSelection()
 showHomeSetup = nodeConfig.needsSetup

 guard !didBootstrap else { return }
 didBootstrap = true

 do {
 try CorpusBootstrap.seedSwiftDataIfNeeded(context: context, mapItems: mapHubs)
 statusMessage = homeMapHub.map { "\($0.name) ready · \(mapHubs.count) hubs in region" }
 ?? "\(mapHubs.count) hubs ready. Set your home hub"
 await refreshFromFeeds()
 } catch {
 lastError = error.localizedDescription
 statusMessage = "\(mapHubs.count) hubs · SwiftData: \(error.localizedDescription)"
 print("HubNode SwiftData seed error: \(error)")
 }
 }

 func reloadCorpus() async {
 isBusy = true
 defer { isBusy = false }
 guard loadMapHubsFromDisk() else { return }
 applyHomeHubSelection()
 do {
 try CorpusBootstrap.reseedSwiftData(context: context, mapItems: mapHubs)
 statusMessage = "Reloaded \(mapHubs.count) hubs"
 await refreshFromFeeds()
 } catch {
 lastError = error.localizedDescription
 statusMessage = "Map has \(mapHubs.count) hubs · store reseed failed: \(error.localizedDescription)"
 }
 }

 // MARK: - Feeds / situation

 func refreshFromFeeds() async {
 guard !mapHubs.isEmpty else {
 statusMessage = "No hubs. Cannot poll"
 return
 }
 isBusy = true
 defer { isBusy = false }
 do {
 pollLoop = PollLoop(context: context)
 situationService = SituationService(context: context)
 doorFlow = DoorFlowService(context: context, inference: inferenceClient)
 askService = AskService(context: context, inference: inferenceClient)

 try CorpusBootstrap.seedSwiftDataIfNeeded(context: context, mapItems: mapHubs)

 let n = try await pollLoop.poll(at: cursor)
 situations = try situationService.recomputeAll(at: cursor)
 let homeName = homeMapHub?.name ?? "no home hub"
 statusMessage = "\(homeName) · \(mapHubs.count) hubs · \(n) feed items · \(cursor.formatted(date: .omitted, time: .shortened))"
 } catch {
 lastError = error.localizedDescription
 statusMessage = "Poll error: \(error.localizedDescription)"
 print("HubNode poll error: \(error)")
 }
 }

 func setCursor(_ date: Date) {
 cursor = date
 Task { await refreshFromFeeds() }
 }

 func advanceReplay(by hours: Double) {
 let next = min(cursor.addingTimeInterval(hours * 3600), DemoReplay.timelineEnd)
 setCursor(next)
 }

 func togglePauseFeed(_ sourceID: String) {
 let paused = pollLoop.paused.contains(sourceID)
 pollLoop.setPaused(sourceID, paused: !paused)
 statusMessage = !paused ? "Paused \(sourceID)" : "Resumed \(sourceID)"
 Task { await refreshFromFeeds() }
 }

 // MARK: - Inference settings

 func rebuildInference() {
 inferenceClient.rebuildRemote()
 doorFlow = DoorFlowService(context: context, inference: inferenceClient)
 askService = AskService(context: context, inference: inferenceClient)
 }

 func probeInference() async {
 rebuildInference()
 let msg = await inferenceClient.probe()
 // Probe may auto-select a real Ollama model name. Rebuild to apply it.
 rebuildInference()
 nodeConfig.lastProbeMessage = msg
 statusMessage = msg
 }

 // MARK: - Selection / posture

 func posture(for hubID: String) -> Posture {
 situations[hubID]?.posture ?? .green
 }

 func pinColor(for item: HubMapItem) -> Color {
 if showStalenessMode {
 switch item.planCurrency {
 case .current: return .green
 case .ageing: return .yellow
 case .stale: return .orange
 case .missing: return .gray
 }
 }
 return posture(for: item.id).tint
 }

 func selectHub(_ id: String) {
 selectedHubID = id
 showRegionalMap = false
 }

 /// Open the regional MapKit view (pins for all hubs). Does not clear home hub.
 func openRegionalMap() {
 showRegionalMap = true
 }

 func goHome() {
 if let home = homeHubID {
 selectedHubID = home
 showRegionalMap = false
 } else {
 showRegionalMap = false
 }
 }

 var selectedMapHub: HubMapItem? {
 guard let selectedHubID else { return nil }
 return mapHubs.first { $0.id == selectedHubID }
 }

 func unlockCoordinator(code: String) -> Bool {
 if code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == Self.coordinatorCode {
 coordinatorUnlocked = true
 return true
 }
 return false
 }

 var viewLevel: ViewLevel {
 coordinatorUnlocked ? .coordinator : .public
 }

 func ensurePersistedHub(for item: HubMapItem) -> Hub {
 let id = item.id
 let d = FetchDescriptor<Hub>(predicate: #Predicate { $0.id == id })
 let hub: Hub
 if let existing = try? context.fetch(d).first {
 if existing.neighbourIDs != item.neighbourIDs {
 existing.neighbourIDs = item.neighbourIDs
 }
 hub = existing
 } else {
 let created = Hub(
 id: item.id,
 name: item.name,
 taName: item.taName,
 address: item.address,
 latitude: item.latitude,
 longitude: item.longitude,
 crpURL: item.crpURL,
 crpReviewedOn: item.crpReviewedOn,
 neighbourIDs: item.neighbourIDs,
 nAssetsPublic: item.nAssetsPublic,
 nAssetsRestricted: item.nAssetsRestricted
 )
 context.insert(created)
 try? context.save()
 hub = created
 }
 // Assets power Ask + the board. Top up if this hub has none yet
 if hub.assets.isEmpty {
 try? CorpusBootstrap.ensureAssets(for: hub, context: context)
 }
 return hub
 }

 func hub(id: String) -> Hub? {
 let d = FetchDescriptor<Hub>(predicate: #Predicate { $0.id == id })
 return try? context.fetch(d).first
 }

 func mapHub(id: String) -> HubMapItem? {
 mapHubs.first { $0.id == id }
 }

 /// Ask the corpus + model about the current hub.
 func ask(question: String, hub: Hub) async -> AskResultVO {
 let drivers = situations[hub.id]?.drivers ?? []
 let posture = posture(for: hub.id)
 return await askService.answer(
 question: question,
 hub: hub,
 viewLevel: viewLevel,
 posture: posture,
 drivers: drivers
 )
 }
}
