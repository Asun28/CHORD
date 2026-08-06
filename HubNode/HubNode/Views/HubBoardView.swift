import SwiftUI
import SwiftData

struct HubBoardView: View {
 @EnvironmentObject private var app: AppModel
 @Environment(\.modelContext) private var modelContext
 let hub: Hub
 var mapItem: HubMapItem? = nil
 var isHome: Bool = false

 @Query(sort: \RoleDef.priorityRank) private var roles: [RoleDef]
 @State private var showDoor = false
 @State private var showTeamManage = false
 @State private var showUnlock = false
 @State private var unlockCode = ""
 @State private var summary: SituationSummary?

 private var snap: SituationSnapshot? {
 app.situations[hub.id]
 }

 private var visibleAssets: [HubAsset] {
 hub.assets.filter { asset in
 if app.coordinatorUnlocked { return true }
 return asset.sensitivity == .public
 }
 .sorted { $0.name < $1.name }
 }

 private var session: HubSession? {
 hub.sessions.sorted { $0.openedAt > $1.openedAt }.first
 }

 var body: some View {
 ScrollView {
 VStack(alignment: .leading, spacing: 16) {
 if isHome {
 Label("This device’s hub. Walk-ins, roster, and tasks happen here", systemImage: "house.fill")
 .font(.subheadline.weight(.medium))
 .foregroundStyle(.secondary)
 .padding(10)
 .frame(maxWidth: .infinity, alignment: .leading)
 .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
 } else {
 HStack {
 Label("Browsing another hub", systemImage: "map")
 .font(.subheadline)
 .foregroundStyle(.secondary)
 Spacer()
 if app.homeHubID != nil {
 Button("Back to your hub") { app.goHome() }
 .buttonStyle(.bordered)
 }
 }
 }

 PostureBanner(
 posture: snap?.posture ?? .green,
 hubName: hub.name,
 summary: summary?.prose
 )

 hubMeta

 if let snap {
 situationTiles(snap)
 }

 AskPanel(
 hub: hub,
 posture: snap?.posture ?? .green,
 drivers: snap?.drivers ?? []
 )

 rolesStrip
 tasksSection
 assetsSection
 neighboursSection
 }
 .padding()
 }
 .navigationTitle(isHome ? "Your hub" : hub.name)
 .toolbar {
 ToolbarItemGroup(placement: .primaryAction) {
 Button {
 showDoor = true
 } label: {
 Label("Walk-in", systemImage: "plus.circle")
 }
 .help("Register a volunteer: first + last name, role, first tasks")

 Button {
 ensureSessionThenManage()
 } label: {
 Label("Manage team", systemImage: "list.bullet")
 }
 .help("Remove people, change roles, mark tasks done")

 Button {
 showUnlock = true
 } label: {
 Label(
 app.coordinatorUnlocked ? "Coordinator" : "Unlock",
 systemImage: app.coordinatorUnlocked ? "lock.open" : "lock"
 )
 }
 .help("Shows restricted facilities (medical, ECE, aged care). Demo code: HUBKIT. Does not change posture or Ask catalogue.")

 Button {
 Task { await loadSummary() }
 } label: {
 Label("Summarise", systemImage: "text.quote")
 }
 .help("Rewrite the situation banner in plain language from live drivers (Ollama/LM Studio if on, else local brief). Does not change posture.")

 if !isHome {
 Button {
 app.setHomeHub(id: hub.id)
 } label: {
 Label("Make this home", systemImage: "house.circle")
 }
 }
 }
 }
 .sheet(isPresented: $showDoor) {
 DoorFlowView(hub: hub)
 .environmentObject(app)
 .frame(minWidth: 520, minHeight: 560)
 }
 .sheet(isPresented: $showTeamManage) {
 if let session {
 TeamManageView(hub: hub, session: session)
 .environmentObject(app)
 }
 }
 .alert("Coordinator unlock", isPresented: $showUnlock) {
 SecureField("Kit code", text: $unlockCode)
 Button("Unlock") {
 _ = app.unlockCoordinator(code: unlockCode)
 unlockCode = ""
 }
 Button("Lock", role: .destructive) {
 app.coordinatorUnlocked = false
 }
 Button("Cancel", role: .cancel) {}
 } message: {
 Text("Unlocks restricted locations on this board (welfare picture). Kit code with the lanyards. Demo: \(AppModel.coordinatorCode). Not the same as Manage team.")
 }
 .task(id: hub.id) {
 await loadSummary()
 }
 }

 private var hubMeta: some View {
 HStack(spacing: 20) {
 labeled("TA", hub.taName)
 labeled("Address", hub.address)
 labeled("Plan", hub.crpReviewedOn ?? "none")
 labeled("Currency", hub.planCurrency.rawValue)
 Spacer()
 }
 .font(.caption)
 .foregroundStyle(.secondary)
 }

 private func labeled(_ k: String, _ v: String) -> some View {
 VStack(alignment: .leading) {
 Text(k.uppercased()).font(.caption2).foregroundStyle(.tertiary)
 Text(v)
 }
 }

 @ViewBuilder
 private func situationTiles(_ snap: SituationSnapshot) -> some View {
 VStack(alignment: .leading, spacing: 8) {
 Text("Situation")
 .font(.headline)

 if snap.drivers.isEmpty && snap.annotations.isEmpty {
 Text("No active drivers for this hub at the current cursor.")
 .foregroundStyle(.secondary)
 }

 LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
 ForEach(snap.drivers) { d in
 DriverTile(driver: d, raising: true)
 }
 ForEach(snap.annotations) { d in
 DriverTile(driver: d, raising: false)
 }
 }

 if !snap.degradedSources.isEmpty {
 Label(
 "Degraded feeds: \(snap.degradedSources.joined(separator: ", "))",
 systemImage: "exclamationmark.triangle"
 )
 .font(.caption)
 .foregroundStyle(.orange)
 }
 }
 }

 /// Team roster: one card per WREMO role. Designed so HTML can mirror the same rows.
 private var rolesStrip: some View {
 VStack(alignment: .leading, spacing: 10) {
 HStack {
 Text("Team roster")
 .font(.headline)
 Spacer()
 let filled = session?.assignments.count ?? 0
 Text("\(filled) assigned")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 Text("First + last name and role code are the fields a future HTML board will bind to.")
 .font(.caption2)
 .foregroundStyle(.tertiary)

 LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
 ForEach(roles, id: \.code) { role in
 let assignees = (session?.assignments ?? []).filter { $0.roleCode == role.code }
 VStack(alignment: .leading, spacing: 6) {
 HStack {
 Text(role.name)
 .font(.subheadline.weight(.semibold))
 .lineLimit(2)
 Spacer(minLength: 0)
 if role.isPriority {
 Text("P\(role.priorityRank)")
 .font(.caption2.weight(.bold))
 .padding(.horizontal, 5)
 .padding(.vertical, 2)
 .background(Color.accentColor.opacity(0.2), in: Capsule())
 }
 }
 Text(role.code)
 .font(.caption2.monospaced())
 .foregroundStyle(.tertiary)

 if assignees.isEmpty {
 Text("Unfilled")
 .font(.caption)
 .foregroundStyle(.secondary)
 } else {
 ForEach(Array(assignees.enumerated()), id: \.offset) { _, a in
 VStack(alignment: .leading, spacing: 1) {
 Text(a.personName.isEmpty ? "\(a.resolvedFirstName) \(a.resolvedLastName)" : a.personName)
 .font(.caption.weight(.semibold))
 if !a.resolvedLastName.isEmpty || !a.firstName.isEmpty {
 Text("\(a.resolvedFirstName) · \(a.resolvedLastName)")
 .font(.caption2)
 .foregroundStyle(.secondary)
 }
 }
 }
 }
 }
 .padding(10)
 .frame(maxWidth: .infinity, alignment: .leading)
 .background(
 assignees.isEmpty
 ? Color.secondary.opacity(0.08)
 : Color.green.opacity(0.12),
 in: RoundedRectangle(cornerRadius: 8)
 )
 }
 }

 if let session, !session.assignments.isEmpty {
 // People list. Flat table shape for web handoff
 VStack(alignment: .leading, spacing: 6) {
 Text("People on duty")
 .font(.subheadline.weight(.semibold))
 ForEach(Array(session.assignments.sorted(by: { $0.assignedAt < $1.assignedAt }).enumerated()), id: \.offset) { _, a in
 let roleName = roles.first(where: { $0.code == a.roleCode })?.name ?? a.roleCode
 HStack {
 Text("\(a.resolvedFirstName) \(a.resolvedLastName)".trimmingCharacters(in: .whitespaces))
 .font(.subheadline.weight(.medium))
 Spacer()
 Text(roleName)
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 .padding(.vertical, 2)
 }
 }
 .padding(10)
 .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
 }
 }
 }

 private var tasksSection: some View {
 VStack(alignment: .leading, spacing: 8) {
 HStack {
 Text("Tasks")
 .font(.headline)
 Spacer()
 if session != nil {
 Button("Manage…") { ensureSessionThenManage() }
 .font(.caption)
 }
 }
 let tasks = session?.tasks.sorted { lhs, rhs in
 if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
 return lhs.createdAt < rhs.createdAt
 } ?? []
 if tasks.isEmpty {
 Text("No tasks yet. Use Walk-in to add people, then Manage team to tick tasks off.")
 .foregroundStyle(.secondary)
 } else {
 ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
 HStack(alignment: .top, spacing: 10) {
 Button {
 toggleTask(task)
 } label: {
 Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
 .foregroundStyle(task.isDone ? .green : .secondary)
 }
 .buttonStyle(.plain)
 VStack(alignment: .leading, spacing: 4) {
 Text(task.text)
 .font(.body)
 .strikethrough(task.isDone)
 .foregroundStyle(task.isDone ? .secondary : .primary)
 HStack {
 if let name = task.assigneeName {
 Text(name).font(.caption.weight(.medium))
 }
 Text(task.roleCode).font(.caption.monospaced()).foregroundStyle(.secondary)
 Spacer()
 Text(task.sourceRef)
 .font(.caption2)
 .foregroundStyle(.tertiary)
 }
 }
 }
 .padding(10)
 .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
 }
 }
 }
 }

 private func ensureSessionThenManage() {
 do {
 _ = try app.doorFlow.openSession(hub: hub)
 showTeamManage = true
 } catch {
 // openSession is unlikely to fail; surface on status if needed
 app.statusMessage = error.localizedDescription
 }
 }

 private func toggleTask(_ task: SessionTask) {
 try? app.doorFlow.setTaskDone(task, done: !task.isDone)
 }

 private var assetsSection: some View {
 AssetBrowserView(
 assets: visibleAssets,
 isCoordinator: app.coordinatorUnlocked,
 restrictedWithheldHint: hub.nAssetsRestricted
 )
 }

 private var neighboursSection: some View {
 VStack(alignment: .leading, spacing: 8) {
 Text("Neighbouring hubs")
 .font(.headline)
 let neighbourIDs = mapItem?.neighbourIDs ?? hub.neighbourIDs
 if neighbourIDs.isEmpty {
 Text("None linked")
 .foregroundStyle(.secondary)
 } else {
 ForEach(neighbourIDs, id: \.self) { nid in
 if let n = app.mapHub(id: nid) {
 Button {
 app.selectHub(nid)
 } label: {
 HStack {
 Text(n.name)
 Spacer()
 Text(app.posture(for: nid).title)
 .foregroundStyle(app.posture(for: nid).tint)
 }
 }
 .buttonStyle(.plain)
 } else {
 Text(nid).foregroundStyle(.secondary)
 }
 }
 }
 }
 }

 private func loadSummary() async {
 guard let snap else {
 summary = nil
 return
 }
 summary = try? await app.inference.summariseSituation(
 drivers: snap.drivers,
 hubName: hub.name,
 posture: snap.posture
 )
 }
}

struct DriverTile: View {
 let driver: SituationDriver
 let raising: Bool

 var body: some View {
 VStack(alignment: .leading, spacing: 6) {
 HStack {
 Text(driver.hazardClass.rawValue.uppercased())
 .font(.caption2.weight(.bold))
 .foregroundStyle(.secondary)
 Spacer()
 AgeBadge(ageSeconds: driver.ageSeconds, isStale: driver.isStale)
 }
 Text(driver.headline)
 .font(.subheadline.weight(.semibold))
 .fixedSize(horizontal: false, vertical: true)
 HStack {
 Text(driver.trustTier.label)
 .font(.caption2)
 if !raising {
 Text("annotate only")
 .font(.caption2)
 .foregroundStyle(.secondary)
 }
 Spacer()
 }
 if driver.isStale {
 Text("Last update \(driver.ageLabel). Feed may be down.")
 .font(.caption2)
 .foregroundStyle(.orange)
 }
 Text(driver.attribution)
 .font(.caption2)
 .foregroundStyle(.tertiary)
 }
 .padding(10)
 .background(
 RoundedRectangle(cornerRadius: 10)
 .fill(driver.isStale ? Color.orange.opacity(0.08) : Color.secondary.opacity(0.06))
 )
 .overlay {
 RoundedRectangle(cornerRadius: 10)
 .strokeBorder(driver.isStale ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
 }
 }
}
