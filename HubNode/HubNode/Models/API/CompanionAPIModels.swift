import Foundation

// MARK: - Companion-shaped JSON DTOs (HTTP board)
/// Projection shapes for the web console. Field names stay snake_case-friendly
/// so the Companion HTML and seed schema can share contracts.

public struct CompanionHealthDTO: Codable, Sendable {
 public var ok: Bool
 public var service: String
 public var version: String
 public var time: String
}

public struct CompanionBootstrapDTO: Codable, Sendable {
 public var api_base: String
 public var hub_id: String?
 public var hub_name: String?
 public var mode: String
 public var replay: Bool
 public var cursor: String
 public var attribution: String
 public var fictional_notice: String
 public var endpoints: [String]
 /// Read-only view of the node model agent. Configure only in HubNode Settings (SwiftUI).
 public var kea: CompanionKeaAgentDTO
}

/// Shared Ask / Kea agent status. Configuration is owned by NodeConfig via SwiftUI Settings only.
public struct CompanionKeaAgentDTO: Codable, Sendable {
 public var name: String
 public var pathway: String
 public var inference_enabled: Bool
 public var model: String
 public var base_url: String
 public var configured: Bool
 public var config_source: String
 public var note: String
}

public struct CompanionStatusDTO: Codable, Sendable {
 public var hub_id: String
 public var hub_name: String
 public var ta_name: String
 public var address: String
 public var posture: String
 public var posture_title: String
 public var session_open: Bool
 public var session_id: String?
 public var opened_at: String?
 public var coordinator_unlocked: Bool
 public var view_level: String
 public var replay_mode: Bool
 public var cursor: String
 public var status_message: String
 public var attribution: String
}

public struct CompanionDriverDTO: Codable, Sendable {
 public var id: String
 public var source_id: String
 public var headline: String
 public var observed_at: String
 public var age_label: String
 public var trust_tier: String
 public var severity: String
 public var hazard_class: String
 public var attribution: String
 public var is_stale: Bool
 public var source_type: String
}

public struct CompanionSituationDTO: Codable, Sendable {
 public var hub_id: String
 public var computed_at: String
 public var cursor: String
 public var posture: String
 public var drivers: [CompanionDriverDTO]
 public var annotations: [CompanionDriverDTO]
 public var degraded_sources: [String]
 public var sit_items: [CompanionSitItemDTO]
}

public struct CompanionSitItemDTO: Codable, Sendable {
 public var id: String
 public var ts: String
 public var location: String
 public var whats_happening: String
 public var our_response: String
 public var priority: String
 public var source_type: String
 public var confirmed: Bool
}

public struct CompanionRosterDTO: Codable, Sendable {
 public var hub_id: String
 public var hub_name: String
 public var session_id: String?
 public var opened_at: String?
 public var posture: String
 public var people: [CompanionPersonDTO]
 public var open_tasks: [CompanionTaskDTO]
 public var roles: [CompanionRoleDTO]
}

public struct CompanionPersonDTO: Codable, Sendable, Identifiable {
 public var id: String
 public var first_name: String
 public var last_name: String
 public var display_name: String
 public var role_code: String
 public var role_name: String
 public var priority_rank: Int?
 public var assigned_at: String
 public var rationale: String
}

public struct CompanionTaskDTO: Codable, Sendable, Identifiable {
 public var id: String
 public var template_id: String
 public var role_code: String
 public var text: String
 public var source_ref: String
 public var status: String
 public var assignee_name: String?
 public var created_at: String
 public var priority: String?
 public var how: [String]?
 public var when: String?
 public var where_text: String?
 public var title: String?
}

public struct CompanionRoleDTO: Codable, Sendable {
 public var code: String
 public var name: String
 public var priority_rank: Int
 public var filled: Bool
 public var people: [String]
}

public struct CompanionAskRequestDTO: Codable, Sendable {
 public var q: String
 public var role: String?
 public var lang: String?
}

public struct CompanionAskResponseDTO: Codable, Sendable {
 public var question: String
 public var answer: String
 public var mode: String
 public var mode_label: String
 public var citations: [CompanionCitationDTO]
 public var unknowns: [String]
 public var hub_id: String
 public var hub_name: String
 public var intent: String
 public var passages: [CompanionPassageDTO]
 public var kea: CompanionKeaAgentDTO
}

public struct CompanionPassageDTO: Codable, Sendable {
 public var origin: String
 public var source_ref: String
 public var text: String
}

public struct CompanionCitationDTO: Codable, Sendable {
 public var kind: String
 public var source_ref: String
 public var detail: String
 public var label: String
}

// MARK: - Phase 2 surfaces

public struct CompanionMonitorDTO: Codable, Sendable {
 public var hub_id: String
 public var cursor: String
 public var feeds: [CompanionFeedDTO]
 public var items: [CompanionMonitorItemDTO]
 public var merge_note: String
}

public struct CompanionFeedDTO: Codable, Sendable {
 public var id: String
 public var name: String
 public var endpoint: String?
 public var licence: String?
 public var poll: String?
 public var fetched: String?
 public var paused: Bool
 public var live: Bool
 public var attribution: String?
}

public struct CompanionMonitorItemDTO: Codable, Sendable {
 public var id: String
 public var feed: String
 public var severity: String
 public var time: String
 public var title: String
 public var detail: String
 public var lat: Double?
 public var lng: Double?
 public var source: String
 public var is_stale: Bool
}

public struct CompanionMyShiftDTO: Codable, Sendable {
 public var hub_id: String
 public var hub_name: String
 public var role: String
 public var role_code: String?
 public var person: String?
 public var posture: String
 public var runbook: [String]
 public var my_jobs: [CompanionTaskDTO]
 public var unassigned_for_role: [CompanionTaskDTO]
 public var finished: [CompanionTaskDTO]
 public var note: String
}

public struct CompanionNeedDTO: Codable, Sendable, Identifiable {
 public var id: String
 public var ts: String
 public var description: String
 public var name: String
 public var contact: String?
 public var category: String
 public var life_threatening: Bool
 public var status: String
 public var routing: String?
}

public struct CompanionOfferDTO: Codable, Sendable, Identifiable {
 public var id: String
 public var ts: String
 public var description: String
 public var name: String
 public var contact: String?
 public var category: String
 public var status: String
}

public struct CompanionNeedsOffersDTO: Codable, Sendable {
 public var needs: [CompanionNeedDTO]
 public var offers: [CompanionOfferDTO]
 public var matches: [[String: String]]
 public var note: String
}

public struct CompanionPublicInfoDTO: Codable, Sendable {
 public var items: [CompanionPublicInfoItemDTO]
 public var large_print: Bool
 public var hub_disclaimer: String
}

public struct CompanionPublicInfoItemDTO: Codable, Sendable, Identifiable {
 public var id: String
 public var ts: String
 public var source: String
 public var message: String
}

public struct CompanionRunbooksDTO: Codable, Sendable {
 public var note: String
 public var roles: [String: [String]]
}

enum CompanionJSON {
 static let iso: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f
 }()

 static let isoBasic: ISO8601DateFormatter = {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime]
  return f
 }()

 static func encode<T: Encodable>(_ value: T) throws -> Data {
  let enc = JSONEncoder()
  enc.outputFormatting = [.sortedKeys]
  enc.dateEncodingStrategy = .iso8601
  return try enc.encode(value)
 }

 static func dateString(_ date: Date) -> String {
  iso.string(from: date)
 }

 static func parseDate(_ s: String?) -> Date? {
  guard let s, !s.isEmpty else { return nil }
  return iso.date(from: s) ?? isoBasic.date(from: s)
 }
}
