import SwiftUI

/// Scannable hub assets: feature water/kit first, group the rest, search long lists.
/// Flat 40-row dumps bury the water tank under every dairy and church in the CRP.
struct AssetBrowserView: View {
 let assets: [HubAsset]
 let isCoordinator: Bool
 let restrictedWithheldHint: Int

 @State private var query = ""
 @State private var expandPlaces = false
 @State private var expandRestricted = false

 private var buckets: AssetBuckets {
 AssetBuckets(assets: assets, query: query)
 }

 var body: some View {
 VStack(alignment: .leading, spacing: 10) {
 header

 if !buckets.essentials.isEmpty {
 sectionLabel("Essentials at this hub")
 ForEach(buckets.essentials, id: \.name) { asset in
 essentialRow(asset)
 }
 }

 if !buckets.places.isEmpty {
 DisclosureGroup(isExpanded: $expandPlaces) {
 LazyVStack(alignment: .leading, spacing: 6) {
 ForEach(buckets.places, id: \.name) { asset in
 placeRow(asset)
 }
 }
 .padding(.top, 6)
 } label: {
 HStack {
 Label("Nearby places & facilities", systemImage: "mappin.and.ellipse")
 .font(.subheadline.weight(.semibold))
 Spacer()
 Text("\(buckets.places.count)")
 .font(.caption.monospacedDigit())
 .foregroundStyle(.secondary)
 }
 }
 }

 if isCoordinator {
 if !buckets.restricted.isEmpty {
 DisclosureGroup(isExpanded: $expandRestricted) {
 LazyVStack(alignment: .leading, spacing: 6) {
 ForEach(buckets.restricted, id: \.name) { asset in
 placeRow(asset, restricted: true)
 }
 }
 .padding(.top, 6)
 } label: {
 HStack {
 Label("Restricted (coordinator)", systemImage: "lock.fill")
 .font(.subheadline.weight(.semibold))
 .foregroundStyle(.orange)
 Spacer()
 Text("\(buckets.restricted.count)")
 .font(.caption.monospacedDigit())
 .foregroundStyle(.orange)
 }
 }
 }
 } else if restrictedWithheldHint > 0 {
 Text("\(restrictedWithheldHint) restricted facilities hidden. Unlock with kit code for welfare picture.")
 .font(.caption)
 .foregroundStyle(.secondary)
 }

 if buckets.essentials.isEmpty && buckets.places.isEmpty && buckets.restricted.isEmpty {
 Text(query.isEmpty ? "No assets loaded for this view." : "No assets match “\(query)”.")
 .font(.callout)
 .foregroundStyle(.secondary)
 }
 }
 }

 private var header: some View {
 VStack(alignment: .leading, spacing: 8) {
 HStack {
 Text("Hub resources")
 .font(.headline)
 Spacer()
 Text(isCoordinator ? "coordinator" : "public")
 .font(.caption)
 .foregroundStyle(isCoordinator ? .orange : .secondary)
 }
 // Summary chips
 HStack(spacing: 8) {
 chip("Water", count: buckets.waterCount, tint: .blue)
 chip("Places", count: buckets.places.count, tint: .secondary)
 if isCoordinator {
 chip("Restricted", count: buckets.restricted.count, tint: .orange)
 }
 }
 TextField("Filter places…", text: $query)
 .textFieldStyle(.roundedBorder)
 }
 }

 private func chip(_ title: String, count: Int, tint: Color) -> some View {
 Text("\(title) \(count)")
 .font(.caption.weight(.semibold))
 .padding(.horizontal, 8)
 .padding(.vertical, 4)
 .background(tint.opacity(0.12), in: Capsule())
 .foregroundStyle(tint == .secondary ? Color.primary : tint)
 }

 private func sectionLabel(_ text: String) -> some View {
 Text(text.uppercased())
 .font(.caption2.weight(.bold))
 .foregroundStyle(.secondary)
 }

 private func essentialRow(_ asset: HubAsset) -> some View {
 HStack(alignment: .top, spacing: 10) {
 Image(systemName: icon(for: asset))
 .font(.title3)
 .foregroundStyle(.blue)
 .frame(width: 28)
 VStack(alignment: .leading, spacing: 2) {
 Text(asset.name)
 .font(.subheadline.weight(.semibold))
 Text(friendlyKind(asset.kind))
 .font(.caption2)
 .foregroundStyle(.secondary)
 }
 Spacer()
 }
 .padding(10)
 .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
 }

 private func placeRow(_ asset: HubAsset, restricted: Bool = false) -> some View {
 HStack(alignment: .top, spacing: 8) {
 Image(systemName: restricted ? "lock.fill" : "building.2")
 .font(.caption)
 .foregroundStyle(restricted ? .orange : .secondary)
 .frame(width: 16)
 Text(asset.name)
 .font(.subheadline)
 .foregroundStyle(.primary)
 Spacer()
 }
 .padding(.vertical, 2)
 }

 private func icon(for asset: HubAsset) -> String {
 switch asset.kind {
 case "emergency_water": return "drop.fill"
 default:
 let n = asset.name.lowercased()
 if n.contains("kit") { return "shippingbox.fill" }
 if n.contains("school") || n.contains("hall") { return "building.columns.fill" }
 return "star.fill"
 }
 }

 private func friendlyKind(_ kind: String) -> String {
 switch kind {
 case "emergency_water": return "Emergency water"
 case "public_place": return "Public place"
 case "restricted_facility": return "Restricted facility"
 default: return kind.replacingOccurrences(of: "_", with: " ")
 }
 }
}

// MARK: - Grouping

private struct AssetBuckets {
 var essentials: [HubAsset]
 var places: [HubAsset]
 var restricted: [HubAsset]
 var waterCount: Int

 init(assets: [HubAsset], query: String) {
 let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
 func matches(_ a: HubAsset) -> Bool {
 q.isEmpty || a.name.lowercased().contains(q)
 }

 let filtered = assets.filter(matches)
 var water: [HubAsset] = []
 var hubLike: [HubAsset] = []
 var place: [HubAsset] = []
 var rest: [HubAsset] = []

 for a in filtered {
 if a.sensitivity == .restricted || a.kind == "restricted_facility" {
 rest.append(a)
 continue
 }
 if a.kind == "emergency_water" || a.name.localizedCaseInsensitiveContains("water tank") {
 water.append(a)
 } else if Self.isHubEssential(a) {
 hubLike.append(a)
 } else {
 place.append(a)
 }
 }

 // Dedupe near-identical names within essentials
 essentials = Self.dedupe(water + hubLike)
 places = Self.dedupe(place).sorted { $0.name < $1.name }
 restricted = Self.dedupe(rest).sorted { $0.name < $1.name }
 waterCount = water.count
 }

 private static func isHubEssential(_ a: HubAsset) -> Bool {
 let n = a.name.lowercased()
 return n.contains("hub kit")
 || n.contains("emergency hub")
 || (n.contains("school") && n.split(separator: ",").count <= 2 && a.kind == "public_place" && n.count < 60)
 }

 private static func dedupe(_ list: [HubAsset]) -> [HubAsset] {
 var seen = Set<String>()
 var out: [HubAsset] = []
 for a in list {
 let key = a.name.collapsedWhitespace.lowercased()
 if seen.insert(key).inserted {
 out.append(a)
 }
 }
 return out
 }
}
