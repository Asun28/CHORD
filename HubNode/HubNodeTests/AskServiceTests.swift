import XCTest
import SwiftData
@testable import HubNode

/// Ask feature — the properties that have to hold before this goes on a projector:
/// the privacy gate, absent plans, hub scoping, life without a model, and
/// instructions that come from WREMO's catalogue rather than from prose generation.
@MainActor
final class AskServiceTests: XCTestCase {

    private let restrictedName = "Sunnybrook Rest Home, 12 Hidden Lane, Newtown"

    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
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
        let config = ModelConfiguration("AskTests", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - Inference doubles
    //
    // Deterministic on purpose: the degraded tier is a thing we test, not a thing
    // we claim. Nothing here touches NodeConfig or the network.

    /// No endpoint configured — the state a hall laptop is in by default.
    private func noModel() -> any AskInferenceClient { NoModelClient() }

    /// Configured but cold: the call throws.
    private func coldModel() -> any AskInferenceClient { ColdModelClient() }

    /// Configured, the call returns text, but it came from the deterministic
    /// fallback rather than a model. Must NOT be labelled as summarised.
    private func fallbackModel() -> any AskInferenceClient { FallbackModelClient() }

    /// Configured and a model genuinely answered.
    private func liveModel() -> any AskInferenceClient { LiveModelClient() }

    @discardableResult
    private func insertHub(
        _ context: ModelContext,
        id: String,
        name: String,
        reviewedOn: String?,
        neighbourIDs: [String] = [],
        restrictedCount: Int = 0
    ) -> Hub {
        let hub = Hub(
            id: id,
            name: name,
            taName: "Wellington City",
            address: "1 Test Street, \(name)",
            latitude: -41.31,
            longitude: 174.78,
            crpURL: reviewedOn == nil ? nil : "https://example.invalid/\(id).pdf",
            crpReviewedOn: reviewedOn,
            neighbourIDs: neighbourIDs,
            nAssetsPublic: 1,
            nAssetsRestricted: restrictedCount
        )
        context.insert(hub)
        return hub
    }

    private func insertAsset(
        _ context: ModelContext,
        hub: Hub,
        kind: String,
        name: String,
        sensitivity: AssetSensitivity
    ) {
        let asset = HubAsset(kind: kind, name: name, sensitivity: sensitivity, hub: hub)
        hub.assets.append(asset)
        context.insert(asset)
    }

    private func seedGuide(_ context: ModelContext) {
        context.insert(GuideChunk(
            section: "Setting up",
            part: 0,
            text: "Identify a safe working space and set up the Community Emergency Hub kit. "
                + "Find the emergency water tank and check the taps before you open.",
            sourceRef: "WREMO Wellington Region Hub Guide — Setting up"
        ))
        context.insert(GuideChunk(
            section: "Before you open",
            part: 0,
            text: "Decide as a community whether to open the hub. Check that the buildings are safe first.",
            sourceRef: "WREMO Wellington Region Hub Guide — Before you open"
        ))
    }

    private func seedCatalogue(_ context: ModelContext) {
        context.insert(RoleDef(
            code: "reception",
            name: "Reception",
            roleDescription: "Welcomes people arriving at the hub and directs them to the right place.",
            priorityRank: 3,
            sourceRef: "WREMO Hub Guide — Working as a team"
        ))
        context.insert(RoleDef(
            code: "facility_maintenance",
            name: "Facility Maintenance",
            roleDescription: "Keeps the building and grounds usable.",
            priorityRank: 6,
            sourceRef: "WREMO Hub Guide — Working as a team"
        ))
        context.insert(TaskTemplate(
            id: "tt-900",
            roleCode: "reception",
            phase: .setup,
            text: "Set up a welcome table at the entrance",
            sourceRef: "WREMO Wellington Region Hub Guide — Setting up"
        ))
        context.insert(TaskTemplate(
            id: "tt-901",
            roleCode: "hub_supervisor",
            phase: .before_open,
            text: "Confirm with the team that the hub is ready to open",
            sourceRef: "WREMO Wellington Region Hub Guide — Before you open"
        ))
    }

    private func planPassage(
        hubID: String,
        part: Int,
        section: String,
        text: String,
        reviewedOn: String? = "2025-06"
    ) -> RetrievedPassageVO {
        RetrievedPassageVO(
            id: "\(hubID)#\(part)",
            origin: .hubPlan,
            hubID: hubID,
            section: section,
            text: text,
            sourceRef: "\(hubID) Community Response Plan"
                + (reviewedOn == nil ? "" : " (reviewed \(reviewedOn!))"),
            reviewedOn: reviewedOn
        )
    }

    // MARK: - (a) The privacy gate

    func testPublicViewCannotSurfaceRestrictedAssetViaAsk() async throws {
        let context = try makeContext()
        seedGuide(context)
        seedCatalogue(context)
        let hub = insertHub(context, id: "newtown", name: "Newtown", reviewedOn: "2025-06", restrictedCount: 1)
        insertAsset(context, hub: hub, kind: "emergency_water", name: "Emergency water tank, Newtown School", sensitivity: .public)
        insertAsset(context, hub: hub, kind: "restricted_facility", name: restrictedName, sensitivity: .restricted)
        try context.save()

        let plans = PlanChunkStore(passages: [
            planPassage(
                hubID: "newtown",
                part: 0,
                section: "Where can people stay?",
                text: "The nearest rest home is \(restrictedName). Residents may need help to leave their homes."
            ),
            planPassage(
                hubID: "newtown",
                part: 1,
                section: "Infrastructure",
                text: "The emergency water tank sits beside the school hall taps."
            ),
        ])
        let service = AskService(context: context, inference: noModel(), planChunks: plans)
        let question = "Where is the nearest rest home for older residents?"

        let board = await service.answer(
            question: question,
            hub: hub,
            viewLevel: .public,
            posture: .watch,
            drivers: []
        )

        for needle in ["Sunnybrook", "Hidden Lane", "rest home"] {
            XCTAssertFalse(
                board.answer.containsInsensitive(needle),
                "Board-view answer leaked '\(needle)'"
            )
        }
        for passage in board.passages {
            XCTAssertFalse(passage.text.containsInsensitive("Sunnybrook"), "Board view retrieved a restricted passage")
        }
        for citation in board.citations {
            XCTAssertFalse(citation.label.containsInsensitive("Sunnybrook"))
        }
        XCTAssertTrue(
            board.unknowns.contains { $0.containsInsensitive("withheld") },
            "Board view must say something was withheld rather than imply nothing exists"
        )

        // Same question, coordinator view: the gate is what changed, not the corpus.
        let coordinator = await service.answer(
            question: question,
            hub: hub,
            viewLevel: .coordinator,
            posture: .watch,
            drivers: []
        )
        let coordinatorText = coordinator.answer + coordinator.passages.map(\.text).joined(separator: " ")
        XCTAssertTrue(
            coordinatorText.containsInsensitive("Sunnybrook"),
            "Coordinator view should be able to see the restricted facility"
        )
    }

    func testPublicViewFactLookupNeverMapsRestrictedRows() throws {
        let context = try makeContext()
        let hub = insertHub(context, id: "newtown", name: "Newtown", reviewedOn: "2025-06", restrictedCount: 1)
        insertAsset(context, hub: hub, kind: "emergency_water", name: "Emergency water tank, Newtown School", sensitivity: .public)
        insertAsset(context, hub: hub, kind: "restricted_facility", name: restrictedName, sensitivity: .restricted)
        try context.save()

        let store = HubFactStore(context: context, planChunks: PlanChunkStore(passages: []))

        let board = store.disclosableAssets(for: hub, viewLevel: .public)
        XCTAssertTrue(board.assets.allSatisfy { $0.sensitivity == .public })
        XCTAssertFalse(board.assets.contains { $0.name.containsInsensitive("Sunnybrook") })
        XCTAssertGreaterThan(board.withheldCount, 0)

        let unlocked = store.disclosableAssets(for: hub, viewLevel: .coordinator)
        XCTAssertTrue(unlocked.assets.contains { $0.name.containsInsensitive("Sunnybrook") })
        XCTAssertEqual(unlocked.withheldCount, 0)
    }

    // MARK: - (b) Absence is representable

    func testHubWithNoPlanSaysSoAndNeverBorrowsANeighboursPlan() async throws {
        let context = try makeContext()
        seedGuide(context)
        seedCatalogue(context)
        let neighbour = insertHub(context, id: "eastbourne", name: "Eastbourne", reviewedOn: "2025-01")
        let hub = insertHub(
            context,
            id: "days-bay",
            name: "Days Bay",
            reviewedOn: nil,
            neighbourIDs: [neighbour.id]
        )
        try context.save()

        // The neighbour has plan prose. The hub under test has none.
        let plans = PlanChunkStore(passages: [
            planPassage(
                hubID: "eastbourne",
                part: 0,
                section: "Infrastructure",
                text: "Eastbourne's emergency water tank is behind the Muritai School hall."
            ),
        ])
        let service = AskService(context: context, inference: noModel(), planChunks: plans)

        let result = await service.answer(
            question: "Where is our emergency water tank?",
            hub: hub,
            viewLevel: .coordinator,
            posture: .green,
            drivers: []
        )

        XCTAssertEqual(result.planCurrency, .missing)
        XCTAssertNil(result.planReviewedOn)
        XCTAssertTrue(
            result.answer.containsInsensitive("no published Community Response Plan"),
            "Expected an explicit no-plan statement, got:\n\(result.answer)"
        )
        XCTAssertTrue(result.unknowns.contains { $0.containsInsensitive("No published Community Response Plan") })
        XCTAssertFalse(
            result.answer.containsInsensitive("Muritai"),
            "A hub with no plan must never be answered out of a neighbour's plan"
        )
        XCTAssertTrue(result.passages.allSatisfy { $0.hubID == nil }, "Only regional guide prose should have matched")
    }

    // MARK: - (c) Retrieval is scoped to this hub

    func testRetrievalNeverReturnsAnotherHubsPlan() async throws {
        let context = try makeContext()
        seedGuide(context)
        seedCatalogue(context)
        let alpha = insertHub(context, id: "alpha", name: "Alpha", reviewedOn: "2025-03")
        insertHub(context, id: "bravo", name: "Bravo", reviewedOn: "2025-04")
        try context.save()

        let plans = PlanChunkStore(passages: [
            planPassage(hubID: "alpha", part: 0, section: "Infrastructure",
                        text: "The Alpha emergency water tank is behind the kitchen."),
            planPassage(hubID: "bravo", part: 0, section: "Infrastructure",
                        text: "The Bravo emergency water tank zzzmarker is at the rear of the hall."),
        ])
        let service = AskService(context: context, inference: noModel(), planChunks: plans)

        let result = await service.answer(
            question: "Where is the emergency water tank?",
            hub: alpha,
            viewLevel: .coordinator,
            posture: .green,
            drivers: []
        )

        XCTAssertFalse(result.passages.isEmpty, "Alpha's own plan should have matched")
        for passage in result.passages {
            XCTAssertTrue(
                passage.hubID == nil || passage.hubID == "alpha",
                "Retrieved a passage scoped to \(passage.hubID ?? "nil")"
            )
            XCTAssertFalse(passage.text.containsInsensitive("zzzmarker"))
        }
        XCTAssertFalse(result.answer.containsInsensitive("zzzmarker"))
        XCTAssertFalse(result.citations.contains { $0.sourceRef.containsInsensitive("bravo") })

        // The store itself refuses to widen.
        XCTAssertEqual(plans.passages(forHubID: "alpha").count, 1)
        XCTAssertTrue(plans.passages(forHubID: "charlie").isEmpty)
    }

    // MARK: - (d) Life without a model

    func testNoModelConfiguredStillReturnsPassagesVerbatim() async throws {
        let context = try makeContext()
        seedGuide(context)
        seedCatalogue(context)
        let hub = insertHub(context, id: "newtown", name: "Newtown", reviewedOn: "2025-06")
        try context.save()

        let plans = PlanChunkStore(passages: [
            planPassage(hubID: "newtown", part: 0, section: "Infrastructure",
                        text: "The emergency water tank is beside the Newtown School hall."),
        ])
        let client = noModel()
        XCTAssertFalse(client.isRemoteConfigured)

        let service = AskService(context: context, inference: client, planChunks: plans)
        let result = await service.answer(
            question: "Where is the emergency water tank?",
            hub: hub,
            viewLevel: .coordinator,
            posture: .green,
            drivers: []
        )

        XCTAssertEqual(result.mode, .notSummarised)
        XCTAssertTrue(result.isDegraded)
        XCTAssertFalse(result.answer.isEmpty)
        XCTAssertFalse(result.passages.isEmpty, "Passages are the answer when nothing can summarise")
        XCTAssertTrue(result.modeLabel.containsInsensitive("verbatim"))
        XCTAssertTrue(
            result.passages.contains { $0.text.containsInsensitive("beside the Newtown School hall") },
            "Retrieved passage text must survive verbatim"
        )
    }

    func testUnreachableModelDegradesLikeNoModel() async throws {
        let context = try makeContext()
        seedGuide(context)
        seedCatalogue(context)
        let hub = insertHub(context, id: "newtown", name: "Newtown", reviewedOn: "2025-06")
        try context.save()

        let plans = PlanChunkStore(passages: [
            planPassage(hubID: "newtown", part: 0, section: "Infrastructure",
                        text: "The emergency water tank is beside the Newtown School hall."),
        ])
        let client = coldModel()
        XCTAssertTrue(client.isRemoteConfigured, "This case is *configured* but cold")

        let service = AskService(context: context, inference: client, planChunks: plans)
        let result = await service.answer(
            question: "Where is the emergency water tank?",
            hub: hub,
            viewLevel: .coordinator,
            posture: .green,
            drivers: []
        )

        XCTAssertEqual(
            result.mode, .notSummarised,
            "A cold endpoint must never be labelled as a model summary"
        )
        XCTAssertFalse(result.passages.isEmpty)
        XCTAssertTrue(
            result.unknowns.contains { $0.containsInsensitive("did not answer") || $0.containsInsensitive("unavailable") },
            "Expected an unknown explaining the model did not answer, got \(result.unknowns)"
        )
    }

    // MARK: - No invented instructions

    func testSetupStepsAreQuotedFromTheTaskCatalogue() async throws {
        let context = try makeContext()
        seedGuide(context)
        seedCatalogue(context)
        let hub = insertHub(context, id: "newtown", name: "Newtown", reviewedOn: "2025-06")
        try context.save()

        let service = AskService(
            context: context,
            inference: noModel(),
            planChunks: PlanChunkStore(passages: [])
        )
        let result = await service.answer(
            question: "How do I set up?",
            hub: hub,
            viewLevel: .coordinator,
            posture: .green,
            drivers: []
        )

        XCTAssertEqual(result.intent, .setup)
        XCTAssertTrue(
            result.answer.containsInsensitive("Set up a welcome table at the entrance"),
            "Setup steps must be the catalogue rows, got:\n\(result.answer)"
        )
        XCTAssertTrue(result.citations.contains { $0.kind == .taskCatalogue && $0.detail == "tt-900" })
        // Every catalogue citation must name a real template id from the store.
        let templateIDs = Set(try context.fetch(FetchDescriptor<TaskTemplate>()).map(\.id))
        for citation in result.citations where citation.kind == .taskCatalogue {
            XCTAssertTrue(templateIDs.contains(citation.detail), "Cited unknown template \(citation.detail)")
        }
    }

    func testRoleQuestionNarrowsToTheRoleAsked() async throws {
        let context = try makeContext()
        seedGuide(context)
        seedCatalogue(context)
        let hub = insertHub(context, id: "newtown", name: "Newtown", reviewedOn: "2025-06")
        try context.save()

        let service = AskService(
            context: context,
            inference: noModel(),
            planChunks: PlanChunkStore(passages: [])
        )
        let result = await service.answer(
            question: "What does Reception do?",
            hub: hub,
            viewLevel: .coordinator,
            posture: .green,
            drivers: []
        )

        XCTAssertEqual(result.intent, .role)
        XCTAssertTrue(result.answer.containsInsensitive("Welcomes people arriving at the hub"))
        XCTAssertFalse(
            result.answer.containsInsensitive("Facility Maintenance"),
            "A question about Reception should not dump the whole catalogue"
        )
        XCTAssertTrue(result.citations.contains { $0.kind == .roleCatalogue && $0.detail == "Reception" })
    }

    // MARK: - Bundled plan prose

    func testBundledPlanProseCoversPublishedPlansOnly() throws {
        let store = PlanChunkStore()
        XCTAssertGreaterThan(store.hubCount, 100, "plan_chunks.jsonl should be bundled or resolvable from source")

        let items = try CorpusBootstrap.loadMapItems()
        let withPlan = items.filter { $0.planCurrency != .missing }
        let withoutPlan = items.filter { $0.planCurrency == .missing }

        for item in withoutPlan {
            XCTAssertTrue(
                store.passages(forHubID: item.id).isEmpty,
                "\(item.id) has no published plan but plan prose was found"
            )
        }
        let covered = withPlan.filter { !store.passages(forHubID: $0.id).isEmpty }
        XCTAssertGreaterThan(covered.count, 100, "Expected plan prose for ~114 hubs, got \(covered.count)")

        let sample = try XCTUnwrap(covered.first)
        for passage in store.passages(forHubID: sample.id) {
            XCTAssertEqual(passage.hubID, sample.id)
        }
    }

    // MARK: - Honest labelling

    func testDeterministicFallbackIsNeverLabelledSummarised() async throws {
        let context = try makeContext()
        seedGuide(context)
        seedCatalogue(context)
        let hub = insertHub(context, id: "newtown", name: "Newtown", reviewedOn: "2025-06")
        try context.save()

        let service = AskService(
            context: context,
            inference: fallbackModel(),
            planChunks: PlanChunkStore(passages: [])
        )
        let result = await service.answer(
            question: "Where is the emergency water tank?",
            hub: hub,
            viewLevel: .coordinator,
            posture: .green,
            drivers: []
        )

        XCTAssertEqual(result.mode, .notSummarised, "Fallback text must not claim a model spoke")
        XCTAssertNotEqual(result.answer, FallbackModelClient.text, "Grounded answer should be kept")
        XCTAssertTrue(result.unknowns.contains { $0.containsInsensitive("did not answer") })
    }

    func testLiveModelSummarisesButCitationsStayAppOwned() async throws {
        let context = try makeContext()
        seedGuide(context)
        seedCatalogue(context)
        let hub = insertHub(context, id: "newtown", name: "Newtown", reviewedOn: "2025-06")
        try context.save()

        let service = AskService(
            context: context,
            inference: liveModel(),
            planChunks: PlanChunkStore(passages: [
                planPassage(hubID: "newtown", part: 0, section: "Infrastructure",
                            text: "The emergency water tank is beside the Newtown School hall."),
            ])
        )
        let result = await service.answer(
            question: "Where is the emergency water tank?",
            hub: hub,
            viewLevel: .coordinator,
            posture: .green,
            drivers: []
        )

        XCTAssertEqual(result.mode, .summarised)
        XCTAssertEqual(result.answer, LiveModelClient.prose)
        XCTAssertFalse(result.passages.isEmpty, "Passages stay on the board even when summarised")
        XCTAssertFalse(result.citations.isEmpty)
        XCTAssertFalse(
            result.citations.contains { $0.sourceRef.containsInsensitive("Invented Source") },
            "A citation the app never supplied must not survive"
        )
    }
}

// MARK: - Doubles
//
// `AskInferenceClient` (declared in AskService.swift) is class-bound and covers
// only what Ask needs, so these stubs stay small and no URLSession is involved.

@MainActor
private final class NoModelClient: AskInferenceClient {
    var isRemoteConfigured: Bool { false }
    var lastAnswerCameFromModel: Bool { false }
    var lastRemoteError: String? { nil }
    func rebuildRemote() {}

    func answerQuestion(question: String, chunks: [String], hubName: String) async throws -> Answer {
        XCTFail("Ask must not call the model when no endpoint is configured")
        return Answer(answer: "", citations: [], unknowns: [])
    }
}

@MainActor
private final class ColdModelClient: AskInferenceClient {
    struct ModelDown: LocalizedError {
        var errorDescription: String? { "model unreachable" }
    }

    var isRemoteConfigured: Bool { true }
    var lastAnswerCameFromModel: Bool { false }
    var lastRemoteError: String? { "model unreachable" }
    func rebuildRemote() {}

    func answerQuestion(question: String, chunks: [String], hubName: String) async throws -> Answer {
        throw ModelDown()
    }
}

/// Configured, and the call returns text — but the deterministic fallback wrote it.
@MainActor
private final class FallbackModelClient: AskInferenceClient {
    static let text = "Deterministic fallback text, written by no model at all."

    var isRemoteConfigured: Bool { true }
    var lastAnswerCameFromModel: Bool { false }
    var lastRemoteError: String? { "connection refused" }
    func rebuildRemote() {}

    func answerQuestion(question: String, chunks: [String], hubName: String) async throws -> Answer {
        Answer(answer: Self.text, citations: [], unknowns: [])
    }
}

@MainActor
private final class LiveModelClient: AskInferenceClient {
    static let prose = "The emergency water tank is beside the Newtown School hall."

    var isRemoteConfigured: Bool { true }
    var lastAnswerCameFromModel: Bool { true }
    var lastRemoteError: String? { nil }
    func rebuildRemote() {}

    func answerQuestion(question: String, chunks: [String], hubName: String) async throws -> Answer {
        Answer(answer: Self.prose, citations: ["Invented Source — page 99"], unknowns: [])
    }
}
