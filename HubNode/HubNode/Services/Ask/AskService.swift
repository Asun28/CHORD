import Foundation
import SwiftData

// MARK: - Flow: Ask (playbook Q&A)
/// Intent → structured hub facts (gated) → retrieve plan/guide prose (gated) →
/// deterministic grounded answer → optional local-model rewrite.
/// Model never fetches data; never raises posture; must not be labelled "summarised"
/// unless `lastAnswerCameFromModel` is true (architecture.md §2, §6, §8).

/// Testable surface for the generative step of Ask.
@MainActor
protocol AskInferenceClient: AnyObject {
 var isRemoteConfigured: Bool { get }
 /// Honesty flag: only true when a remote model actually produced the last answer.
 var lastAnswerCameFromModel: Bool { get }
 var lastRemoteError: String? { get }
 func rebuildRemote()
 func answerQuestion(question: String, chunks: [String], hubName: String) async throws -> Answer
}

@MainActor
final class AskService {
 private let context: ModelContext
 private let facts: HubFactStore
 private let inference: any AskInferenceClient

 /// `planChunks` is a test seam only. Production passes nil and gets the
 /// process-wide bundle-backed store.
 init(
 context: ModelContext,
 inference: any AskInferenceClient,
 planChunks: PlanChunkStore? = nil
 ) {
 self.context = context
 self.facts = HubFactStore(context: context, planChunks: planChunks)
 self.inference = inference
 }

 func answer(
 question: String,
 hub: Hub,
 viewLevel: ViewLevel,
 posture: Posture,
 drivers: [SituationDriver]
 ) async -> AskResultVO {
 let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
 let intent = AskIntentClassifier.classify(q)
 // Structured assets + playbook catalogue must be present for real answers
 if hub.assets.isEmpty {
 try? CorpusBootstrap.ensureAssets(for: hub, context: context)
 }
 try? CorpusBootstrap.ensurePlaybookSeeded(context: context)

 let hubFacts = facts.facts(for: hub, viewLevel: viewLevel, posture: posture, drivers: drivers)
 var retrieval = facts.retrieve(question: q, hub: hub, viewLevel: viewLevel, limit: 6)
 if intent == .setup || intent == .openDecision {
 retrieval = facts.augmentForSetup(base: retrieval, hub: hub, viewLevel: viewLevel)
 }

 let tasks = catalogueTasks(for: intent, question: q, hubFacts: hubFacts)

 // Deterministic grounded answer always available
 let grounded = GroundedAnswerBuilder.build(
 question: q,
 intent: intent,
 facts: hubFacts,
 passages: retrieval.passages,
 withheldPassageCount: retrieval.withheldPassageCount,
 tasks: tasks
 )

 // Optional model rewrite of the grounded answer (citations stay app-owned)
 var mode: AskResultVO.Mode = .notSummarised
 var answerText = grounded.answer
 var citations = grounded.citations
 var unknowns = grounded.unknowns

 // Always rebuild from current Settings, then resolve a real model id.
 // Default "local-model" is not a real Ollama/LM Studio name and used to make
 // every Ask look like the model was never called.
 inference.rebuildRemote()
 if let composite = inference as? CompositeInferenceClient {
  _ = await composite.ensureRemoteReady()
 }

 if inference.isRemoteConfigured {
 // Full hub + plan pack + explicit setup steps for the model
 let combined = ModelContextPack.build(
 question: q,
 intent: intent,
 facts: hubFacts,
 passages: retrieval.passages,
 groundedAnswer: grounded.answer,
 tasks: tasks
 )
 do {
 let modelAnswer = try await inference.answerQuestion(
 question: q,
 chunks: combined,
 hubName: hub.name
 )
 let prose = modelAnswer.answer.trimmingCharacters(in: .whitespacesAndNewlines)
 // Only label as model-sourced when the remote path actually ran.
 if inference.lastAnswerCameFromModel, !prose.isEmpty {
 answerText = prose
 // App-owned citations remain; merge model ones if useful
 if citations.isEmpty {
 citations = modelAnswer.citations.map {
 CitationVO(kind: .guideSection, sourceRef: $0)
 }
 }
 unknowns = Array(Set(unknowns + modelAnswer.unknowns)).sorted()
 mode = .summarised
 } else {
 let detail = inference.lastRemoteError
 ?? "endpoint returned no usable content"
 unknowns.append(
 "Model did not answer (\(detail)). Showing grounded corpus answer."
 )
 // Prefixed note so web/Mac UI make the failure obvious
 answerText =
  "Model path did not complete (\(detail)). Grounded corpus answer follows.\n\n"
  + grounded.answer
 }
 } catch {
 unknowns.append("Model unavailable: \(error.localizedDescription)")
 answerText =
  "Model unavailable (\(error.localizedDescription)). Grounded corpus answer follows.\n\n"
  + grounded.answer
 }
 } else {
 unknowns.append("Local model off. Grounded corpus answer only. Enable in Settings.")
 }

 return AskResultVO(
 question: q,
 hubID: hub.id,
 hubName: hub.name,
 viewLevel: viewLevel,
 intent: intent,
 mode: mode,
 answer: answerText,
 passages: retrieval.passages,
 citations: citations,
 unknowns: unknowns,
 planReviewedOn: hubFacts.planReviewedOn,
 planCurrency: hubFacts.planCurrency
 )
 }

 // MARK: - Catalogue lookup

 /// Anything that tells a volunteer what to *do* is selected from WREMO's task
 /// catalogue, never composed here (ADR-005). The model gets these as text it
 /// may reorder or quote; it cannot author a replacement.
 private func catalogueTasks(
 for intent: AskIntent,
 question: String,
 hubFacts: HubFactsVO
 ) -> [TaskLineVO] {
 // Top up catalogue if a prior seed skipped templates
 try? CorpusBootstrap.ensurePlaybookSeeded(context: context)

 switch intent {
 case .setup:
 // Full opening sequence: access → team → setup → before_open
 var rows = facts.taskLines(
 phases: [.access, .team, .setup, .before_open],
 limit: 16
 )
 if rows.isEmpty {
 rows = SetupFallback.tasks
 }
 return rows
 case .openDecision:
 var rows = facts.taskLines(phases: [.access, .before_open, .team], limit: 10)
 if rows.isEmpty { rows = SetupFallback.tasks }
 return rows
 case .role:
 guard let role = RoleMatcher.matchedRole(question: question, roles: hubFacts.roles) else {
 return facts.taskLines(phases: [.team, .setup], limit: 6)
 }
 return facts.taskLines(phases: TaskPhase.allCases, roleCode: role.code, limit: 6)
 case .place, .neighbours, .plan, .general:
 return []
 }
 }
}

/// Guaranteed setup steps when SwiftData catalogue is empty (still WREMO-aligned text).
enum SetupFallback {
 static let tasks: [TaskLineVO] = [
 TaskLineVO(id: "fb-1", roleCode: "facility_maintenance", phase: .access,
 text: "Check that the environment around the facility is safe",
 sourceRef: "WREMO Hub Guide - Accessing the hub"),
 TaskLineVO(id: "fb-2", roleCode: "facility_maintenance", phase: .access,
 text: "Check that the buildings are safe",
 sourceRef: "WREMO Hub Guide - Accessing the hub"),
 TaskLineVO(id: "fb-3", roleCode: "facility_maintenance", phase: .access,
 text: "Locate the hub kit and keys, or leave a note if relocating",
 sourceRef: "WREMO Hub Guide - Accessing the hub"),
 TaskLineVO(id: "fb-4", roleCode: "facility_maintenance", phase: .access,
 text: "Identify a safe working space",
 sourceRef: "WREMO Hub Guide - Accessing the hub"),
 TaskLineVO(id: "fb-5", roleCode: "hub_supervisor", phase: .team,
 text: "Fill the four priority roles first from whoever is available",
 sourceRef: "WREMO Hub Guide - Working as a team"),
 TaskLineVO(id: "fb-6", roleCode: "hub_supervisor", phase: .team,
 text: "Agree who is doing what and write the roster where everyone can see it",
 sourceRef: "WREMO Hub Guide - Working as a team"),
 TaskLineVO(id: "fb-7", roleCode: "information_coord", phase: .setup,
 text: "Create the situation board with space for source and age on every fact",
 sourceRef: "WREMO Hub Guide - Setting up"),
 TaskLineVO(id: "fb-8", roleCode: "public_information", phase: .setup,
 text: "Put up public messaging posters, which are in the Hub Kit",
 sourceRef: "WREMO Hub Guide - Setting up"),
 TaskLineVO(id: "fb-9", roleCode: "needs_and_offers", phase: .setup,
 text: "Set up Needs and Offers boards so requests and resources can be matched",
 sourceRef: "WREMO Hub Guide - Setting up"),
 TaskLineVO(id: "fb-10", roleCode: "communications", phase: .team,
 text: "Establish contact with the Emergency Operations Centre when able",
 sourceRef: "WREMO Hub Guide - Working as a team"),
 TaskLineVO(id: "fb-11", roleCode: "public_information", phase: .before_open,
 text: "Put up clear signage that the Hub is running",
 sourceRef: "WREMO Hub Guide - Before you open"),
 TaskLineVO(id: "fb-12", roleCode: "reception", phase: .before_open,
 text: "Explain the purpose of the hub to new arrivals in plain language",
 sourceRef: "WREMO Hub Guide - Before you open"),
 ]
}

/// "What does Reception do?" should answer about Reception, not list all eight.
enum RoleMatcher {
 static func matchedRole(question: String, roles: [RoleVO]) -> RoleVO? {
 let terms = Set(question.askTokens)
 guard !terms.isEmpty else { return nil }
 return roles.first { role in
 !Set(role.name.askTokens).union(role.code.askTokens).isDisjoint(with: terms)
 }
 }
}

// MARK: - Intent

enum AskIntentClassifier {
 static func classify(_ question: String) -> AskIntent {
 let q = question.lowercased()
 if matches(q, ["open", "opening", "activate", "should we open", "safe to open"]) {
 return .openDecision
 }
 if matches(q, [
 "setup", "set up", "setting up", "whiteboard", "key", "keys", "lockbox",
 "how do i set", "how do we set", "how do we open", "activate", "activation",
 "what should we do", "first steps", "get started", "start the hub", "open the hub",
 ]) {
 return .setup
 }
 // Assets / places / water. Before general, so the model gets the structured list
 if matches(q, [
 "water", "tank", "facility", "facilities", "school", "where is", "place", "places",
 "resource", "resources", "toilet", "asset", "assets", "available", "equipment",
 "supplies", "what do we have", "what have we", "inventory", "stock", "venue",
 "kit", "where can", "what's at", "whats at",
 ]) {
 return .place
 }
 if matches(q, ["role", "roles", "reception", "supervisor", "roster", "who does", "lanyard"]) {
 return .role
 }
 if matches(q, ["neighbour", "neighbor", "nearby hub", "other hub", "next hub"]) {
 return .neighbours
 }
 if matches(q, ["plan", "stale", "reviewed", "current", "crp", "response plan"]) {
 return .plan
 }
 return .general
 }

 private static func matches(_ q: String, _ keys: [String]) -> Bool {
 keys.contains { q.contains($0) }
 }
}

// MARK: - Deterministic grounded prose

enum GroundedAnswerBuilder {
 struct Built {
 var answer: String
 var citations: [CitationVO]
 var unknowns: [String]
 }

 static func build(
 question: String,
 intent: AskIntent,
 facts: HubFactsVO,
 passages: [RetrievedPassageVO],
 withheldPassageCount: Int,
 tasks: [TaskLineVO] = []
 ) -> Built {
 var lines: [String] = []
 var citations: [CitationVO] = [facts.hubRecordCitation]
 var unknowns: [String] = []

 lines.append("**\(facts.name)** · posture \(facts.posture.title)")

 // 11 of 125 hubs have no published plan. Say so before answering anything,
 // so no answer can read as if it came from a plan that does not exist.
 if !facts.hasPublishedPlan {
 lines.append(
 "There is no published Community Response Plan for \(facts.name). "
 + "Everything below comes from the regional Hub Guide and this hub's own record. "
 + "no neighbouring hub's plan has been substituted."
 )
 unknowns.append(
 "No published Community Response Plan for \(facts.name). Hub-specific detail could not be determined."
 )
 }

 switch intent {
 case .openDecision:
 lines.append("Opening decision depends on safety of the site and current posture (\(facts.posture.title)).")
 if facts.posture == .green {
 lines.append("No matching hazards right now. Still check building safety and keys before opening.")
 } else {
 lines.append("Active drivers:")
 for d in facts.drivers.prefix(4) {
 lines.append("• \(d.headline) · \(d.ageLabel) · \(d.attribution)")
 citations.append(CitationVO(kind: .observation, sourceRef: d.observationID, detail: d.headline))
 }
 }
 lines.append("Opening a hub is a community decision, not a system decision. Before you open:")
 if tasks.isEmpty {
 unknowns.append("Task catalogue returned no before-open rows")
 } else {
 append(tasks: tasks, to: &lines, citations: &citations)
 }

 case .setup:
 lines.append("How to set up **this hub** (\(facts.name) · \(facts.address)):")
 if let water = facts.assets.first(where: { $0.kind == "emergency_water" }) {
 lines.append("• Emergency water: \(water.name)")
 }
 lines.append("Steps from WREMO's Hub Guide catalogue (do these here. Do not send people to a PDF):")
 append(tasks: tasks.isEmpty ? SetupFallback.tasks : tasks, to: &lines, citations: &citations)

 case .place:
 if facts.assets.isEmpty {
 lines.append("No public place/resource rows available in this view.")
 if facts.restrictedWithheldCount > 0 {
 lines.append("(\(facts.restrictedWithheldCount) restricted facilities withheld from the board view.)")
 }
 } else {
 lines.append("Places and resources for this hub:")
 for a in facts.assets.prefix(12) {
 lines.append("• \(a.name) (\(a.kind))")
 }
 if facts.assets.count > 12 {
 lines.append("…and \(facts.assets.count - 12) more")
 }
 }

 case .role:
 let asked = RoleMatcher.matchedRole(question: question, roles: facts.roles)
 let shown = asked.map { [$0] } ?? facts.roles
 lines.append(asked == nil ? "Official roles (priority 1-4 first):" : "From WREMO's role catalogue:")
 for r in shown {
 let p = r.priorityRank <= 4 ? " · P\(r.priorityRank)" : ""
 lines.append("• \(r.name)\(p). \(r.roleDescription)")
 citations.append(CitationVO(kind: .roleCatalogue, sourceRef: r.sourceRef, detail: r.name))
 }
 if !tasks.isEmpty {
 lines.append("What that role does, from the task catalogue:")
 append(tasks: tasks, to: &lines, citations: &citations)
 }

 case .neighbours:
 if facts.neighbours.isEmpty {
 lines.append("No neighbouring hubs linked in the corpus for this node.")
 unknowns.append("Neighbour list empty")
 } else {
 lines.append("Neighbouring hubs:")
 for n in facts.neighbours {
 lines.append("• \(n.name) · \(n.posture.title) · plan \(n.planCurrency.rawValue)")
 }
 }

 case .plan:
 if facts.hasPublishedPlan {
 lines.append("Published plan · reviewed \(facts.planReviewedOn ?? "unknown") · currency \(facts.planCurrency.rawValue).")
 if let url = facts.planURL {
 lines.append("Source: \(url)")
 }
 if facts.planCurrency == .stale, let reviewed = facts.planReviewedOn {
 unknowns.append("Plan text dates from \(reviewed). More than four years old.")
 }
 } else {
 lines.append("Plan currency: missing.")
 }

 case .general:
 break
 }

 if !passages.isEmpty {
 lines.append("")
 lines.append("From the guide / plan:")
 for p in passages.prefix(3) {
 lines.append("• \(p.section): \(p.text.truncated(to: 280))")
 citations.append(p.citation)
 }
 } else if intent == .general {
 lines.append("No matching guide passages ranked for that question. Try asking about roles, neighbours, water, or setup.")
 unknowns.append("No ranked passages")
 }

 if facts.viewLevel == .public {
 if withheldPassageCount > 0 {
 lines.append("")
 lines.append("(\(withheldPassageCount) relevant passage(s) withheld. Coordinator unlock required.)")
 unknowns.append(
 "\(withheldPassageCount) relevant plan passage(s) withheld because they name restricted facilities."
 )
 }
 if facts.restrictedWithheldCount > 0 {
 unknowns.append(
 "\(facts.restrictedWithheldCount) restricted location(s) withheld in board view. Coordinator unlock lives in the hub kit."
 )
 }
 }

 // Deduplicate citations by id
 var seen = Set<String>()
 let unique = citations.filter { seen.insert($0.id).inserted }

 return Built(
 answer: lines.joined(separator: "\n"),
 citations: unique,
 unknowns: unknowns
 )
 }

 /// Quote the catalogue row and cite its template id. The task text is never
 /// rewritten here, so every instruction on screen traces to a page in the guide.
 private static func append(
 tasks: [TaskLineVO],
 to lines: inout [String],
 citations: inout [CitationVO]
 ) {
 for task in tasks {
 lines.append("• \(task.text) [\(task.phase.title)]")
 citations.append(CitationVO(kind: .taskCatalogue, sourceRef: task.sourceRef, detail: task.id))
 }
 }
}
