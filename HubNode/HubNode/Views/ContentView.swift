import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if app.showHomeSetup {
                HomeHubSetupView()
            } else {
                mainSplit
            }
        }
        .task {
            await app.bootstrapIfNeeded()
        }
    }

    private var mainSplit: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 480)
        } detail: {
            detailPane
        }
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) {
            AttributionBar()
        }
    }

    // MARK: - Sidebar: home-first ops

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            if let home = app.homeMapHub {
                homeCard(home)
            }

            List {
                Section("This hub") {
                    if let home = app.homeMapHub {
                        Button {
                            app.goHome()
                        } label: {
                            Label(home.name, systemImage: "house.fill")
                        }
                        Button {
                            app.goHome()
                            // Door is on the board toolbar
                        } label: {
                            Label("Walk-in / roles", systemImage: "figure.walk.arrival")
                        }
                        .disabled(!app.isViewingHomeHub)
                    } else {
                        Button("Set home hub…") { app.changeHomeHub() }
                    }
                }

                Section("Region") {
                    Button {
                        app.openRegionalMap()
                    } label: {
                        Label(
                            app.showRegionalMap ? "Regional map (showing)" : "Regional map",
                            systemImage: "map"
                        )
                    }
                    Toggle(isOn: $app.showStalenessMode) {
                        Label("Plan age colours", systemImage: "calendar.badge.clock")
                    }
                    .help("Colour pins by CRP currency (SDG 13.1.3), not live posture")
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func homeCard(_ home: HubMapItem) -> some View {
        let posture = app.posture(for: home.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "house.circle.fill")
                    .font(.title)
                    .foregroundStyle(posture.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your hub")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(home.name)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
            }
            HStack {
                Text(posture.title.uppercased())
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(posture.tint.opacity(0.2), in: Capsule())
                Text(home.taName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(home.address)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(posture.tint.opacity(0.08))
        .contentShape(Rectangle())
        .onTapGesture { app.goHome() }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        // Regional map is a full detail mode — not blocked by home hub selection.
        if app.showRegionalMap {
            MapBoardView()
                .navigationTitle("Wellington region")
        } else if let item = app.selectedMapHub ?? app.homeMapHub {
            HubBoardView(
                hub: app.ensurePersistedHub(for: item),
                mapItem: item,
                isHome: item.id == app.homeHubID
            )
        } else {
            ContentUnavailableView {
                Label("Set your hub", systemImage: "house")
            } description: {
                Text("Choose which Community Emergency Hub this device belongs to.")
            } actions: {
                Button("Choose hub…") { app.changeHomeHub() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if app.homeHubID != nil {
                Button {
                    app.goHome()
                } label: {
                    Label("Home", systemImage: "house")
                }
                .disabled(app.isViewingHomeHub && !app.showRegionalMap)
            }

            Button {
                app.changeHomeHub()
            } label: {
                Label("Change hub", systemImage: "house.lodge")
            }

            Button {
                Task { await app.refreshFromFeeds() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(app.isBusy)

            Menu {
                ForEach(FixtureCatalog.sources, id: \.id) { src in
                    Button {
                        app.togglePauseFeed(src.id)
                    } label: {
                        let paused = app.pollLoop.paused.contains(src.id)
                        Label(
                            paused ? "Resume \(src.name)" : "Kill \(src.name)",
                            systemImage: paused ? "play.fill" : "pause.fill"
                        )
                    }
                }
            } label: {
                Label("Feeds", systemImage: "antenna.radiowaves.left.and.right")
            }

            ReplayControls()
        }

        ToolbarItem(placement: .status) {
            Text(app.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ReplayControls: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Replay")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { app.cursor.timeIntervalSince(DemoReplay.timelineStart) },
                    set: { app.setCursor(DemoReplay.timelineStart.addingTimeInterval($0)) }
                ),
                in: 0...(DemoReplay.timelineEnd.timeIntervalSince(DemoReplay.timelineStart))
            )
            .frame(width: 140)
            Text(app.cursor.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .frame(width: 56, alignment: .trailing)
            Button("+1h") { app.advanceReplay(by: 1) }
                .font(.caption)
            Button("+4h") { app.advanceReplay(by: 4) }
                .font(.caption)
        }
    }
}

struct AttributionBar: View {
    var body: some View {
        HStack {
            Text(CorpusBootstrap.attribution)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Text("Local-first · corpus stays with WREMO/GWRC")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
