import Foundation
import SwiftUI

/// Hub operational posture. Rules-owned, never model-owned (architecture.md §5).
public enum Posture: String, Codable, Sendable, CaseIterable, Comparable {
 case green
 case watch
 case act
 case respond

 private var rank: Int {
 switch self {
 case .green: 0
 case .watch: 1
 case .act: 2
 case .respond: 3
 }
 }

 public static func < (lhs: Posture, rhs: Posture) -> Bool {
 lhs.rank < rhs.rank
 }

 public var title: String {
 switch self {
 case .green: "Green"
 case .watch: "Watch"
 case .act: "Act"
 case .respond: "Respond"
 }
 }

 public var subtitle: String {
 switch self {
 case .green: "Nothing matching this hub"
 case .watch: "Advisory or corroborated secondary signal"
 case .act: "Warning affecting this hub's area"
 case .respond: "Hub-relevant event. Consider activation"
 }
 }

 public var tint: Color {
 switch self {
 case .green: .green
 case .watch: .yellow
 case .act: .orange
 case .respond: .red
 }
 }
}
