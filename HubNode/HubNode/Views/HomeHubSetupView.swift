import SwiftUI

/// First-run (and change-home) flow: pick which Community Emergency Hub this device serves.
struct HomeHubSetupView: View {
    @EnvironmentObject private var app: AppModel
    @State private var search = ""
    @State private var selectedTA: String = "All"

    private var territorialAuthorities: [String] {
        let tas = Set(app.mapHubs.map(\.taName)).sorted()
        return ["All"] + tas
    }

    private var filtered: [HubMapItem] {
        app.mapHubs.filter { hub in
            let taOK = selectedTA == "All" || hub.taName == selectedTA
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchOK = q.isEmpty
                || hub.name.localizedCaseInsensitiveContains(q)
                || hub.address.localizedCaseInsensitiveContains(q)
                || hub.taName.localizedCaseInsensitiveContains(q)
            return taOK && searchOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filters
            List(filtered) { hub in
                Button {
                    app.setHomeHub(id: hub.id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: app.homeHubID == hub.id ? "house.circle.fill" : "building.2")
                            .font(.title2)
                            .foregroundStyle(app.homeHubID == hub.id ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hub.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(hub.address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text(hub.taName)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                Text("Plan: \(hub.planCurrency.rawValue)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if app.homeHubID == hub.id {
                            Text("Current")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)

            if app.homeHubID != nil {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        app.showHomeSetup = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which hub is this device in?")
                .font(.title2.weight(.bold))
            Text("This node will default to that hub’s board, roster, and plan. You can still browse the region on the map.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let home = app.homeMapHub {
                Text("Currently: \(home.name)")
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.bar)
    }

    private var filters: some View {
        VStack(spacing: 10) {
            TextField("Search by name or address", text: $search)
                .textFieldStyle(.roundedBorder)
            Picker("Area", selection: $selectedTA) {
                ForEach(territorialAuthorities, id: \.self) { ta in
                    Text(ta).tag(ta)
                }
            }
            .pickerStyle(.menu)
            Text("\(filtered.count) hubs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
