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
                    Label("This device’s hub — walk-ins, roster, and tasks happen here", systemImage: "house.fill")
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
                    Label("Walk-in", systemImage: "figure.walk.arrival")
                }
                Button {
                    showUnlock = true
                } label: {
                    Label(
                        app.coordinatorUnlocked ? "Coordinator" : "Unlock",
                        systemImage: app.coordinatorUnlocked ? "lock.open" : "lock"
                    )
                }
                Button {
                    Task { await loadSummary() }
                } label: {
                    Label("Summarise", systemImage: "text.quote")
                }
                if !isHome {
                    Button {
                        app.setHomeHub(id: hub.id)
                    } label: {
                        Label("Make this home", systemImage: "house.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showDoor) {
            DoorFlowView(hub: hub)
                .environmentObject(app)
                .frame(minWidth: 480, minHeight: 520)
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
            Text("Code lives in the hub kit with the lanyards. Demo code: \(AppModel.coordinatorCode)")
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

    private var rolesStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Roles")
                .font(.headline)
            let filled = Set(session?.assignments.map(\.roleCode) ?? [])
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(roles, id: \.code) { role in
                    let isFilled = filled.contains(role.code)
                    let person = session?.assignments.first(where: { $0.roleCode == role.code })?.personName
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(role.name)
                                .font(.subheadline.weight(.semibold))
                            if role.isPriority {
                                Text("P\(role.priorityRank)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 4)
                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                            }
                        }
                        Text(isFilled ? (person ?? "Filled") : "Unfilled")
                            .font(.caption)
                            .foregroundStyle(isFilled ? .primary : .secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isFilled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tasks")
                .font(.headline)
            let tasks = session?.tasks.sorted { $0.createdAt < $1.createdAt } ?? []
            if tasks.isEmpty {
                Text("No tasks yet — use Walk-in to assign roles from the catalogue.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks, id: \.templateID) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.text)
                            .font(.body)
                        HStack {
                            if let name = task.assigneeName {
                                Text(name).font(.caption.weight(.medium))
                            }
                            Text(task.roleCode).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(task.sourceRef)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assets")
                    .font(.headline)
                if !app.coordinatorUnlocked {
                    Text("public only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("coordinator view")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            let list = visibleAssets.prefix(40)
            ForEach(Array(list), id: \.name) { asset in
                HStack {
                    Text(asset.name)
                    Spacer()
                    if asset.sensitivity == .restricted {
                        Text("restricted")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(asset.kind)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
            }
            if visibleAssets.count > 40 {
                Text("+ \(visibleAssets.count - 40) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                Text("Last update \(driver.ageLabel) — feed may be down.")
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
