import SwiftUI
import SwiftData

@main
struct HubNodeApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                // Share the same container (and mainContext) that AppModel mutates.
                .modelContainer(appModel.container)
        }
        .defaultSize(width: 1280, height: 840)

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .modelContainer(appModel.container)
                .frame(width: 420, height: 360)
        }
    }
}
