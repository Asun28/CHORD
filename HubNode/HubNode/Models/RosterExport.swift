import Foundation

// MARK: - Web / HTML handoff DTOs
/// Stable JSON shape for a future HTML board. Keep field names snake_case-friendly
/// via CodingKeys so a static site or local server can render without Swift.

public struct RosterExportDTO: Codable, Sendable {
 public var hub_id: String
 public var hub_name: String
 public var session_id: String
 public var opened_at: Date
 public var posture: String
 public var people: [RosterPersonDTO]
 public var open_tasks: [RosterTaskDTO]
}

public struct RosterPersonDTO: Codable, Sendable, Identifiable {
 public var id: String
 public var first_name: String
 public var last_name: String
 public var display_name: String
 public var role_code: String
 public var role_name: String
 public var priority_rank: Int?
 public var assigned_at: Date
 public var rationale: String
}

public struct RosterTaskDTO: Codable, Sendable, Identifiable {
 public var id: String
 public var template_id: String
 public var role_code: String
 public var text: String
 public var source_ref: String
 public var status: String
 public var assignee_name: String?
 public var created_at: Date
}

enum RosterExport {
 static let iso: ISO8601DateFormatter = {
 let f = ISO8601DateFormatter()
 f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
 return f
 }()

 static func build(
 hub: Hub,
 session: HubSession,
 roles: [RoleDef],
 posture: Posture
 ) -> RosterExportDTO {
 let roleByCode = Dictionary(uniqueKeysWithValues: roles.map { ($0.code, $0) })
 let people = session.assignments
 .sorted { $0.assignedAt < $1.assignedAt }
 .map { a -> RosterPersonDTO in
 let role = roleByCode[a.roleCode]
 let first = a.resolvedFirstName
 let last = a.resolvedLastName
 return RosterPersonDTO(
 id: "\(a.roleCode)-\(a.assignedAt.timeIntervalSince1970)",
 first_name: first,
 last_name: last,
 display_name: a.personName.isEmpty ? "\(first) \(last)".trimmingCharacters(in: .whitespaces) : a.personName,
 role_code: a.roleCode,
 role_name: role?.name ?? a.roleCode,
 priority_rank: role?.priorityRank,
 assigned_at: a.assignedAt,
 rationale: a.rationale
 )
 }
 let tasks = session.tasks
 .sorted { $0.createdAt < $1.createdAt }
 .map { t in
 RosterTaskDTO(
 id: "\(t.templateID)-\(t.createdAt.timeIntervalSince1970)",
 template_id: t.templateID,
 role_code: t.roleCode,
 text: t.text,
 source_ref: t.sourceRef,
 status: t.statusRaw,
 assignee_name: t.assigneeName,
 created_at: t.createdAt
 )
 }
 return RosterExportDTO(
 hub_id: hub.id,
 hub_name: hub.name,
 session_id: session.id,
 opened_at: session.openedAt,
 posture: posture.rawValue,
 people: people,
 open_tasks: tasks
 )
 }

 static func jsonString(_ dto: RosterExportDTO) -> String? {
 let enc = JSONEncoder()
 enc.outputFormatting = [.prettyPrinted, .sortedKeys]
 enc.dateEncodingStrategy = .iso8601
 guard let data = try? enc.encode(dto) else { return nil }
 return String(data: data, encoding: .utf8)
 }
}
