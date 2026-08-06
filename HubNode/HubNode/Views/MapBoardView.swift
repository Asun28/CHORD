import SwiftUI
import MapKit

/// Regional overview: MapKit pins for all hubs + list with address.
/// Used when the operator needs neighbours / plan-age / posture across Wellington. /// not the day-to-day home-hub board.
struct MapBoardView: View {
 @EnvironmentObject private var app: AppModel

 @State private var cameraPosition: MapCameraPosition = .region(AppModel.wellingtonRegion)

 var body: some View {
 VStack(spacing: 0) {
 headerBar
 mapPane
 .frame(maxHeight: .infinity)
 .layoutPriority(1)

 Divider()

 hubList
 .frame(minHeight: 180, idealHeight: 240, maxHeight: 320)
 }
 .onChange(of: app.corpusGeneration) { _, _ in
 cameraPosition = .region(AppModel.wellingtonRegion)
 }
 .onAppear {
 cameraPosition = .region(AppModel.wellingtonRegion)
 }
 }

 private var headerBar: some View {
 HStack(spacing: 12) {
 VStack(alignment: .leading, spacing: 2) {
 Text("Regional map")
 .font(.headline)
 Text("\(app.mapHubs.count) Community Emergency Hubs · tap a pin or row to open that hub’s board")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 Spacer()
 if app.homeHubID != nil {
 Button {
 app.goHome()
 } label: {
 Label("Back to your hub", systemImage: "house.fill")
 }
 .buttonStyle(.borderedProminent)
 .controlSize(.small)
 }
 Toggle(isOn: $app.showStalenessMode) {
 Text("Plan age")
 }
 .toggleStyle(.button)
 .controlSize(.small)
 .help("Colour by CRP currency (SDG) instead of live posture")
 }
 .padding(.horizontal, 14)
 .padding(.vertical, 10)
 .background(.bar)
 }

 // MARK: - Map

 private var mapPane: some View {
 ZStack(alignment: .topLeading) {
 Map(position: $cameraPosition) {
 ForEach(app.mapHubs) { hub in
 Annotation(hub.name, coordinate: hub.coordinate, anchor: .center) {
 PinView(
 color: app.pinColor(for: hub),
 selected: app.selectedHubID == hub.id,
 isHome: hub.id == app.homeHubID
 )
 .onTapGesture {
 app.selectHub(hub.id)
 }
 }
 .annotationTitles(.hidden)
 }
 }
 .id("hub-map-\(app.corpusGeneration)-\(app.mapHubs.count)")
 .mapStyle(.standard(elevation: .realistic))
 .mapControls {
 MapCompass()
 MapScaleView()
 MapZoomStepper()
 }

 legendCard
 .padding(10)

 if app.mapHubs.isEmpty {
 emptyOverlay
 }
 }
 }

 private var legendCard: some View {
 VStack(alignment: .leading, spacing: 4) {
 Text("\(app.mapHubs.count) hubs")
 .font(.caption.weight(.bold))
 if app.showStalenessMode {
 Text("Colour = plan age (SDG)").font(.caption2).foregroundStyle(.secondary)
 } else {
 Text("Colour = live posture").font(.caption2).foregroundStyle(.secondary)
 }
 LegendView(stalenessMode: app.showStalenessMode)
 if app.homeHubID != nil {
 HStack(spacing: 4) {
 Image(systemName: "house.circle.fill").foregroundStyle(.blue)
 Text("Your hub").font(.caption2)
 }
 }
 }
 .padding(10)
 .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
 }

 private var emptyOverlay: some View {
 VStack(spacing: 10) {
 Text("No map pins")
 .font(.title3.weight(.semibold))
 Text(app.lastError ?? app.statusMessage)
 .font(.caption)
 .foregroundStyle(.secondary)
 .multilineTextAlignment(.center)
 .frame(maxWidth: 280)
 Button("Reload corpus") {
 Task { await app.reloadCorpus() }
 }
 .buttonStyle(.borderedProminent)
 }
 .padding(20)
 .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
 .frame(maxWidth: .infinity, maxHeight: .infinity)
 .background(Color.black.opacity(0.15))
 }

 // MARK: - List

 private var hubList: some View {
 VStack(alignment: .leading, spacing: 0) {
 HStack {
 Text("Hubs by location")
 .font(.subheadline.weight(.semibold))
 Spacer()
 Text("\(app.mapHubs.count)")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 8)

 List(app.mapHubs) { hub in
 Button {
 app.selectHub(hub.id)
 } label: {
 HStack(alignment: .top, spacing: 10) {
 Circle()
 .fill(app.pinColor(for: hub))
 .frame(width: 10, height: 10)
 .padding(.top, 4)
 VStack(alignment: .leading, spacing: 2) {
 HStack {
 Text(hub.name)
 .font(.subheadline.weight(.medium))
 .foregroundStyle(.primary)
 if hub.id == app.homeHubID {
 Image(systemName: "house.fill")
 .font(.caption2)
 .foregroundStyle(.secondary)
 }
 }
 Text(hub.address)
 .font(.caption)
 .foregroundStyle(.secondary)
 .lineLimit(1)
 Text(hub.taName)
 .font(.caption2)
 .foregroundStyle(.tertiary)
 }
 Spacer()
 VStack(alignment: .trailing, spacing: 2) {
 Text(app.posture(for: hub.id).title)
 .font(.caption2.weight(.semibold))
 .foregroundStyle(app.posture(for: hub.id).tint)
 Text(String(format: "%.3f, %.3f", hub.latitude, hub.longitude))
 .font(.caption2.monospaced())
 .foregroundStyle(.tertiary)
 }
 }
 .padding(.vertical, 2)
 }
 .buttonStyle(.plain)
 }
 .listStyle(.inset)
 }
 }
}

struct PinView: View {
 let color: Color
 let selected: Bool
 var isHome: Bool = false

 var body: some View {
 ZStack {
 if isHome {
 Image(systemName: "house.circle.fill")
 .font(.system(size: selected ? 22 : 18))
 .foregroundStyle(color)
 .background(Circle().fill(.white).frame(width: 16, height: 16))
 } else {
 Circle()
 .fill(color)
 .frame(width: selected ? 18 : 14, height: selected ? 18 : 14)
 Circle()
 .strokeBorder(.white, lineWidth: selected ? 2.5 : 1.5)
 .frame(width: selected ? 18 : 14, height: selected ? 18 : 14)
 }
 }
 .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
 .frame(width: 28, height: 28)
 .contentShape(Rectangle())
 }
}

struct LegendView: View {
 let stalenessMode: Bool

 var body: some View {
 Group {
 if stalenessMode {
 VStack(alignment: .leading, spacing: 2) {
 row(.green, "Current ≤24 mo")
 row(.yellow, "Ageing")
 row(.orange, "Stale")
 row(.gray, "No plan")
 }
 } else {
 VStack(alignment: .leading, spacing: 2) {
 row(.green, "Green")
 row(.yellow, "Watch")
 row(.orange, "Act")
 row(.red, "Respond")
 }
 }
 }
 .font(.caption2)
 }

 private func row(_ color: Color, _ label: String) -> some View {
 HStack(spacing: 6) {
 Circle().fill(color).frame(width: 8, height: 8)
 Text(label)
 }
 }
}
