import Foundation
import SwiftData

// MARK: - Project live HubNode state → Companion API DTOs

@MainActor
final class HubNodeAPIService {
 private weak var app: AppModel?
 private let seed = CompanionSeedStore.shared

 init(app: AppModel) {
  self.app = app
  seed.loadIfNeeded()
 }

 func attach(app: AppModel) {
  self.app = app
 }

 // MARK: Routes

 func health() -> CompanionHealthDTO {
  CompanionHealthDTO(
   ok: true,
   service: "HubNode",
   version: "0.2-companion",
   time: CompanionJSON.dateString(Date())
  )
 }

 /// Read-only agent snapshot. Model endpoint is configured only in SwiftUI Settings.
 func keaAgent() -> CompanionKeaAgentDTO {
  let cfg = NodeConfig.shared
  let enabled = cfg.inferenceEnabled
  let base = cfg.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
  let model = cfg.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
  let configured = enabled && cfg.baseURL != nil && !model.isEmpty
  return CompanionKeaAgentDTO(
   name: "Kea",
   pathway: "AskService → CompositeInferenceClient (same as Mac Ask panel)",
   inference_enabled: enabled,
   model: model.isEmpty ? "(none)" : model,
   base_url: base.isEmpty ? "(none)" : base,
   configured: configured,
   config_source: "HubNode Settings (SwiftUI) only. Web clients cannot change the agent.",
   note: configured
    ? "Online model path available. Grounded corpus is always the floor."
    : "On-device grounded answers only until you enable a model in Settings."
  )
 }

 func bootstrap() -> CompanionBootstrapDTO {
  let hub = homeHubMap()
  return CompanionBootstrapDTO(
   api_base: "/api/v1",
   hub_id: hub?.id ?? app?.homeHubID,
   hub_name: hub?.name,
   mode: "live",
   replay: app?.isReplayMode ?? true,
   cursor: CompanionJSON.dateString(app?.cursor ?? Date()),
   attribution: CorpusBootstrap.attribution,
   fictional_notice: "Demo seed content is fictional. Live posture comes from HubNode feeds and rules.",
   endpoints: [
    "GET /health",
    "GET /api/v1/bootstrap",
    "GET /api/v1/hub/status",
    "GET /api/v1/hub/situation",
    "GET /api/v1/hub/roster",
    "GET /api/v1/hub/tasks",
    "GET /api/v1/hub/my-shift",
    "GET /api/v1/hub/monitor",
    "GET /api/v1/hub/needs-offers",
    "GET /api/v1/hub/public-info",
    "GET /api/v1/hub/runbooks",
    "GET /api/v1/hub/kea",
    "GET /api/v1/seed",
    "POST /api/v1/hub/ask",
   ],
   kea: keaAgent()
  )
 }

 func status() throws -> CompanionStatusDTO {
  guard let app else { throw APIError.noApp }
  let map = try requireHomeMap()
  let hub = app.ensurePersistedHub(for: map)
  let session = try? app.doorFlow.openSession(hub: hub)
  let posture = app.posture(for: hub.id)
  return CompanionStatusDTO(
   hub_id: hub.id,
   hub_name: hub.name,
   ta_name: hub.taName,
   address: hub.address,
   posture: posture.rawValue,
   posture_title: posture.title,
   session_open: session != nil,
   session_id: session?.id,
   opened_at: session.map { CompanionJSON.dateString($0.openedAt) },
   coordinator_unlocked: app.coordinatorUnlocked,
   view_level: app.viewLevel.rawValue,
   replay_mode: app.isReplayMode,
   cursor: CompanionJSON.dateString(app.cursor),
   status_message: app.statusMessage,
   attribution: CorpusBootstrap.attribution
  )
  // Note: demo scenario flag is available via bootstrap / settings; status stays lean.
 }

 /// Whether Companion demo scenario feeds are active for Kea status answers.
 func demoScenarioActive() -> Bool {
  NodeConfig.shared.demoScenarioEnabled
 }

 func situation() throws -> CompanionSituationDTO {
  guard let app else { throw APIError.noApp }
  let map = try requireHomeMap()
  let snap = app.situations[map.id]
  let posture = snap?.posture ?? app.posture(for: map.id)

  let rawDrivers = snap?.drivers ?? []
  let rawAnnotations = snap?.annotations ?? []
  let drivers = rawDrivers.map { driverDTO($0, sourceType: "official") }
  let annotations = rawAnnotations.map { driverDTO($0, sourceType: "unconfirmed") }

  var sitItems = rawDrivers.map { d in
   CompanionSitItemDTO(
    id: d.id,
    ts: CompanionJSON.dateString(d.observedAt),
    location: map.name,
    whats_happening: d.headline,
    our_response: d.isStale ? "Feed may be stale. Check age." : "On board. Rules posture applies.",
    priority: priorityForSeverity(d.severity),
    source_type: "official",
    confirmed: true
   )
  }
  let seedItems = seed.sitItems()
  if sitItems.isEmpty {
   sitItems = seedItems
  } else {
   for s in seedItems where !sitItems.contains(where: { $0.id == s.id }) {
    sitItems.append(s)
   }
  }

  return CompanionSituationDTO(
   hub_id: map.id,
   computed_at: CompanionJSON.dateString(snap?.computedAt ?? Date()),
   cursor: CompanionJSON.dateString(snap?.cursor ?? app.cursor),
   posture: posture.rawValue,
   drivers: drivers,
   annotations: annotations,
   degraded_sources: snap?.degradedSources ?? [],
   sit_items: sitItems
  )
 }

 func roster() throws -> CompanionRosterDTO {
  guard let app else { throw APIError.noApp }
  let map = try requireHomeMap()
  let hub = app.ensurePersistedHub(for: map)
  let posture = app.posture(for: hub.id)
  let session = try app.doorFlow.openSession(hub: hub)
  let export = try app.doorFlow.rosterExport(hub: hub, session: session, posture: posture)

  let roles = try app.context.fetch(
   FetchDescriptor<RoleDef>(sortBy: [SortDescriptor(\.priorityRank)])
  )
  let byRole = Dictionary(grouping: export.people, by: \.role_code)
  let roleDTOs = roles.map { r in
   let people = byRole[r.code]?.map(\.display_name) ?? []
   return CompanionRoleDTO(
    code: r.code,
    name: r.name,
    priority_rank: r.priorityRank,
    filled: !people.isEmpty,
    people: people
   )
  }

  return CompanionRosterDTO(
   hub_id: export.hub_id,
   hub_name: export.hub_name,
   session_id: export.session_id,
   opened_at: CompanionJSON.dateString(export.opened_at),
   posture: export.posture,
   people: export.people.map {
    CompanionPersonDTO(
     id: $0.id,
     first_name: $0.first_name,
     last_name: $0.last_name,
     display_name: $0.display_name,
     role_code: $0.role_code,
     role_name: $0.role_name,
     priority_rank: $0.priority_rank,
     assigned_at: CompanionJSON.dateString($0.assigned_at),
     rationale: $0.rationale
    )
   },
   open_tasks: export.open_tasks.map { taskDTO(from: $0) },
   roles: roleDTOs
  )
 }

 func tasks() throws -> [CompanionTaskDTO] {
  let live = try roster().open_tasks
  if !live.isEmpty { return live }
  return seed.seedTasks()
 }

 /// My shift: role-scoped runbook + jobs. Query via role display name or code.
 func myShift(roleQuery: String?) throws -> CompanionMyShiftDTO {
  guard let app else { throw APIError.noApp }
  let map = try requireHomeMap()
  let roster = try roster()
  let runbooks = seed.roleRunbooks()

  // Resolve role: query → first filled person → Hub Supervisor
  let q = roleQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  var roleName = "Hub Supervisor"
  var roleCode: String?
  var person: String?

  if !q.isEmpty {
   if let match = roster.roles.first(where: {
    $0.code.caseInsensitiveCompare(q) == .orderedSame
     || $0.name.localizedCaseInsensitiveContains(q)
   }) {
    roleName = match.name
    roleCode = match.code
    person = match.people.first
   } else if let p = roster.people.first(where: {
    $0.display_name.localizedCaseInsensitiveContains(q)
     || $0.role_name.localizedCaseInsensitiveContains(q)
   }) {
    roleName = p.role_name
    roleCode = p.role_code
    person = p.display_name
   } else {
    roleName = q
    roleCode = seed.roleCode(forDisplayName: q)
   }
  } else if let filled = roster.people.first {
   roleName = filled.role_name
   roleCode = filled.role_code
   person = filled.display_name
  } else if let r = roster.roles.first {
   roleName = r.name
   roleCode = r.code
  }

  let runbook = runbooks.roles[roleName]
   ?? runbooks.roles.first(where: { $0.key.localizedCaseInsensitiveContains(roleName) })?.value
   ?? []

  let allTasks = try tasks()
  let code = roleCode ?? seed.roleCode(forDisplayName: roleName) ?? ""
  let forRole: (CompanionTaskDTO) -> Bool = { t in
   if !code.isEmpty, t.role_code.caseInsensitiveCompare(code) == .orderedSame { return true }
   return t.role_code.localizedCaseInsensitiveContains(roleName)
    || roleName.localizedCaseInsensitiveContains(t.role_code)
  }

  let myJobs = allTasks.filter { t in
   forRole(t)
    && (person == nil || t.assignee_name == person || (t.assignee_name?.isEmpty ?? true) == false && t.assignee_name == person)
    && t.status.lowercased() != "done"
    && !(t.assignee_name?.isEmpty ?? true)
  }
  // If filtering by person emptied the list, show role-scoped open jobs assigned or open
  let jobs: [CompanionTaskDTO]
  if myJobs.isEmpty {
   jobs = allTasks.filter { forRole($0) && $0.status.lowercased() != "done" && !(tOpenUnassigned($0) == false && ($0.assignee_name ?? "").isEmpty) }
    .filter { !(($0.assignee_name ?? "").isEmpty) || $0.status.lowercased() == "doing" || $0.status.lowercased() == "open" }
  } else {
   jobs = myJobs
  }

  let unassigned = allTasks.filter {
   forRole($0) && tOpenUnassigned($0) && $0.status.lowercased() != "done"
  }
  let finished = allTasks.filter {
   forRole($0) && $0.status.lowercased() == "done"
  }

  return CompanionMyShiftDTO(
   hub_id: map.id,
   hub_name: map.name,
   role: roleName,
   role_code: roleCode,
   person: person,
   posture: app.posture(for: map.id).rawValue,
   runbook: runbook,
   my_jobs: jobs.isEmpty ? allTasks.filter { forRole($0) && $0.status.lowercased() != "done" } : jobs,
   unassigned_for_role: unassigned,
   finished: finished,
   note: "Runbook from Companion seed / Hub Guide roles. Jobs from live session tasks, or seed when empty."
  )
 }

 func monitor() throws -> CompanionMonitorDTO {
  guard let app else { throw APIError.noApp }
  let map = try requireHomeMap()
  let cursor = app.cursor

  // Live feed source states
  let feedStates = (try? app.context.fetch(FetchDescriptor<FeedSourceState>())) ?? []
  var feeds: [CompanionFeedDTO] = feedStates.map { s in
   CompanionFeedDTO(
    id: s.id,
    name: s.name,
    endpoint: "hubnode://feed/\(s.id)",
    licence: s.attribution,
    poll: "\(Int(s.cadence / 60)) min",
    fetched: s.lastFetchedAt.map { CompanionJSON.dateString($0) },
    paused: s.isPaused,
    live: true,
    attribution: s.attribution
   )
  }
  // Seed feeds fill gaps
  for sf in seed.monitorFeeds() where !feeds.contains(where: { $0.id == sf.id }) {
   feeds.append(sf)
  }

  // Live observations as monitor items
  let store = ObservationStore(context: app.context)
  let alerts = (try? store.activeAlerts(at: cursor)) ?? []
  var items: [CompanionMonitorItemDTO] = alerts.map { a in
   let age = cursor.timeIntervalSince(a.observedAt)
   let cadences = (try? store.allSourceCadences()) ?? [:]
   let cadence = cadences[a.sourceID] ?? 3600
   let stale = age > cadence * PostureEngine.staleCadenceMultiplier
   return CompanionMonitorItemDTO(
    id: a.id,
    feed: a.sourceID,
    severity: a.severity.rawValue,
    time: CompanionJSON.dateString(a.observedAt),
    title: a.headline,
    detail: a.description,
    lat: a.latitude,
    lng: a.longitude,
    source: "live",
    is_stale: stale
   )
  }

  // Seed items where no live id match
  for s in seed.monitorItems() where !items.contains(where: { $0.id == s.id }) {
   // Prefer live feed coverage: skip seed if same feed already has live items? Keep seed for narrative demo.
   items.append(s)
  }

  // Sort: live first, then by time desc-ish
  items.sort { lhs, rhs in
   if lhs.source != rhs.source { return lhs.source == "live" }
   return lhs.time > rhs.time
  }

  return CompanionMonitorDTO(
   hub_id: map.id,
   cursor: CompanionJSON.dateString(cursor),
   feeds: feeds,
   items: items,
   merge_note: "Live CAP observations override by id. Seed monitor rows fill narrative gaps."
  )
 }

 func needsOffers(includeContacts: Bool) -> CompanionNeedsOffersDTO {
  var needs = seed.needs()
  var offers = seed.offers()
  if !includeContacts {
   needs = needs.map {
    var n = $0
    n = CompanionNeedDTO(
     id: n.id, ts: n.ts, description: n.description, name: n.name,
     contact: nil, category: n.category, life_threatening: n.life_threatening,
     status: n.status, routing: n.routing
    )
    return n
   }
   offers = offers.map {
    CompanionOfferDTO(
     id: $0.id, ts: $0.ts, description: $0.description, name: $0.name,
     contact: nil, category: $0.category, status: $0.status
    )
   }
  }
  return CompanionNeedsOffersDTO(
   needs: needs,
   offers: offers,
   matches: seed.matches().map { dict in
    dict // already [String:String]
   },
   note: includeContacts
    ? "Contacts visible (coordinator / needs role)."
    : "Contacts redacted. Unlock coordinator on the Mac or request role-gated access later."
  )
 }

 func publicInfo() -> CompanionPublicInfoDTO {
  CompanionPublicInfoDTO(
   items: seed.publicInfoItems(),
   large_print: false,
   hub_disclaimer: "Community-run. Not an official CDEM channel. For life-threatening emergencies call 111."
  )
 }

 func runbooks() -> CompanionRunbooksDTO {
  seed.roleRunbooks()
 }

 /// Ask Kea: same pathway as SwiftUI Ask panel (AskService + NodeConfig model).
 /// Web cannot select a different agent; only HubNode Settings configures inference.
 func ask(body: Data) async throws -> CompanionAskResponseDTO {
  guard let app else { throw APIError.noApp }
  let req: CompanionAskRequestDTO
  do {
   req = try JSONDecoder().decode(CompanionAskRequestDTO.self, from: body)
  } catch {
   // Tolerate form-ish payloads and bare JSON edge cases
   if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
    let q = (obj["q"] as? String) ?? (obj["question"] as? String) {
    req = CompanionAskRequestDTO(q: q, role: obj["role"] as? String, lang: obj["lang"] as? String)
   } else if let s = String(data: body, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    req = CompanionAskRequestDTO(q: s, role: nil, lang: nil)
   } else {
    throw APIError.badRequest("Could not parse ask body: \(error.localizedDescription)")
   }
  }
  let q = req.q.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !q.isEmpty else { throw APIError.badRequest("Empty question") }

  // Refresh inference client from SwiftUI Settings, then resolve a real model id
  // before AskService runs (same path as Mac Ask panel).
  app.rebuildInference()
  let readyMsg = await app.inferenceClient.ensureRemoteReady()
  print("HubNode HTTP Ask: \(readyMsg)")

  let map = try requireHomeMap()
  let hub = app.ensurePersistedHub(for: map)
  let result = await app.ask(question: q, hub: hub)
  let agent = keaAgent()

  return CompanionAskResponseDTO(
   question: result.question,
   answer: result.answer,
   answer_html: MarkdownLite.toHTML(result.answer),
   mode: result.mode.rawValue,
   mode_label: result.modeLabel,
   citations: result.citations.map {
    CompanionCitationDTO(
     kind: $0.kind.rawValue,
     source_ref: $0.sourceRef,
     detail: $0.detail,
     label: $0.label
    )
   },
   unknowns: result.unknowns,
   hub_id: result.hubID,
   hub_name: result.hubName,
   intent: result.intent.rawValue,
   passages: result.passages.prefix(6).map {
    CompanionPassageDTO(
     origin: $0.origin.rawValue,
     source_ref: $0.sourceRef,
     text: String($0.text.prefix(800))
    )
   },
   kea: agent
  )
 }

 func seedRaw() throws -> Data {
  seed.loadIfNeeded()
  guard let data = seed.rawJSON else { throw APIError.notFound("Seed not bundled") }
  return data
 }

 // MARK: Helpers

 private func homeHubMap() -> HubMapItem? {
  app?.homeMapHub ?? app?.selectedMapHub
 }

 private func requireHomeMap() throws -> HubMapItem {
  guard let map = homeHubMap() else { throw APIError.noHomeHub }
  return map
 }

 private func driverDTO(_ d: SituationDriver, sourceType: String) -> CompanionDriverDTO {
  CompanionDriverDTO(
   id: d.id,
   source_id: d.sourceID,
   headline: d.headline,
   observed_at: CompanionJSON.dateString(d.observedAt),
   age_label: d.ageLabel,
   trust_tier: d.trustTier.label,
   severity: d.severity.rawValue,
   hazard_class: d.hazardClass.rawValue,
   attribution: d.attribution,
   is_stale: d.isStale,
   source_type: sourceType
  )
 }

 private func taskDTO(from t: RosterTaskDTO) -> CompanionTaskDTO {
  CompanionTaskDTO(
   id: t.id,
   template_id: t.template_id,
   role_code: t.role_code,
   text: t.text,
   source_ref: t.source_ref,
   status: t.status,
   assignee_name: t.assignee_name,
   created_at: CompanionJSON.dateString(t.created_at),
   priority: nil,
   how: nil,
   when: nil,
   where_text: nil,
   title: nil
  )
 }

 private func tOpenUnassigned(_ t: CompanionTaskDTO) -> Bool {
  (t.assignee_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
 }

 private func priorityForSeverity(_ s: String) -> String {
  switch s.lowercased() {
  case "extreme", "severe": return "urgent"
  case "moderate": return "high"
  default: return "normal"
  }
 }

 private func priorityForSeverity(_ s: CAPAlert.Severity) -> String {
  priorityForSeverity(s.rawValue)
 }

 enum APIError: LocalizedError {
  case noApp
  case noHomeHub
  case notFound(String)
  case badRequest(String)
  case methodNotAllowed

  var errorDescription: String? {
   switch self {
   case .noApp: return "HubNode app not attached"
   case .noHomeHub: return "No home hub set. Choose a hub in HubNode first."
   case .notFound(let m): return m
   case .badRequest(let m): return m
   case .methodNotAllowed: return "Method not allowed"
   }
  }

  var statusCode: Int {
   switch self {
   case .noApp: return 503
   case .noHomeHub: return 409
   case .notFound: return 404
   case .badRequest: return 400
   case .methodNotAllowed: return 405
   }
  }
 }
}
