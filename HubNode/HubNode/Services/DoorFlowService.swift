import Foundation
import SwiftData

@MainActor
final class DoorFlowService {
 private let context: ModelContext
 private let inference: any InferenceClient

 init(context: ModelContext, inference: any InferenceClient = OfflineInferenceClient()) {
 self.context = context
 self.inference = inference
 }

 func openSession(hub: Hub, openedBy: String = "Coordinator") throws -> HubSession {
 if let existing = hub.sessions.sorted(by: { $0.openedAt > $1.openedAt }).first {
 return existing
 }
 let session = HubSession(openedBy: openedBy, hub: hub)
 hub.sessions.append(session)
 context.insert(session)
 try context.save()
 return session
 }

 func filledRoleCodes(session: HubSession) -> Set<String> {
 Set(session.assignments.map(\.roleCode))
 }

 func unfilledPriorityRoles(session: HubSession) throws -> [RoleDef] {
 let roles = try context.fetch(
 FetchDescriptor<RoleDef>(sortBy: [SortDescriptor(\.priorityRank)])
 )
 let filled = filledRoleCodes(session: session)
 return roles.filter { $0.isPriority && !filled.contains($0.code) }
 }

 func assignWalkIn(
 session: HubSession,
 firstName: String,
 lastName: String,
 answers: [String: String],
 posture: Posture
 ) async throws -> (Assignment, [SessionTask], RoleSuggestion) {
 let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
 let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
 let displayName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")

 let unfilled = try unfilledPriorityRoles(session: session).map(\.code)
 let suggestion = try await inference.suggestRole(
 answers: answers,
 unfilledPriorityRoles: unfilled
 )

 // If suggested role already filled and priority unfilled remain, force priority
 var roleCode = suggestion.roleCode
 let filled = filledRoleCodes(session: session)
 if filled.contains(roleCode), let firstPriority = unfilled.first {
 roleCode = firstPriority
 }

 let assignment = Assignment(
 firstName: first,
 lastName: last,
 roleCode: roleCode,
 rationale: suggestion.rationale,
 session: session
 )
 session.assignments.append(assignment)
 context.insert(assignment)

 let templates = try context.fetch(FetchDescriptor<TaskTemplate>())
 let dtos = templates.map {
 TaskTemplateDTO(
 id: $0.id,
 roleCode: $0.roleCode,
 phase: $0.phaseRaw,
 text: $0.text,
 sourceRef: $0.sourceRef
 )
 }
 let selected = try await inference.selectTasks(
 posture: posture,
 rolesPresent: [roleCode],
 templates: dtos
 )
 let byID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
 var tasks: [SessionTask] = []
 for sel in selected.prefix(3) {
 guard let t = byID[sel.templateID] else { continue }
 let task = SessionTask(
 templateID: t.id,
 roleCode: t.roleCode,
 text: t.text,
 sourceRef: t.sourceRef,
 reason: sel.reason,
 assigneeName: displayName,
 session: session
 )
 session.tasks.append(task)
 context.insert(task)
 tasks.append(task)
 }
 try context.save()
 return (assignment, tasks, suggestion)
 }

 // MARK: - Manage walk-ins (roster lifecycle)

 /// Remove a person from the roster and drop their still-open tasks.
 /// Completed tasks stay for the session record (audit trail for HTML export).
 func removePerson(_ assignment: Assignment, from session: HubSession) throws {
 let display = assignment.personName
 let openTasks = session.tasks.filter {
 $0.assigneeName == display && !$0.isDone
 }
 for t in openTasks {
 context.delete(t)
 }
 context.delete(assignment)
 try context.save()
 }

 func setTaskDone(_ task: SessionTask, done: Bool) throws {
 task.setDone(done)
 try context.save()
 }

 func changeRole(
 _ assignment: Assignment,
 to roleCode: String,
 session: HubSession
 ) throws {
 assignment.roleCode = roleCode
 try context.save()
 }

 /// Snapshot for board refresh / future HTML.
 func rosterExport(hub: Hub, session: HubSession, posture: Posture) throws -> RosterExportDTO {
 let roles = try context.fetch(
 FetchDescriptor<RoleDef>(sortBy: [SortDescriptor(\.priorityRank)])
 )
 return RosterExport.build(hub: hub, session: session, roles: roles, posture: posture)
 }
}
