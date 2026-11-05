import SwiftUI

/// Connect GitHub until there's a token, then the three tabs. Owns the app-wide reactions:
/// scene phase (refresh policy), deep links, and Window switches.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.auth.isSignedIn {
                AppTabs()
            } else {
                ConnectView()
            }
        }
        .onOpenURL { app.open($0) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: Task { await app.sceneDidBecomeActive() }
            case .background: app.sceneDidEnterBackground()
            default: break
            }
        }
        .onChange(of: app.store.selectedWindow) {
            Task { await app.windowDidChange() }
        }
        .task {
            #if DEBUG
            // Simulator checks of the real device flow, where nobody can tap Connect.
            if ProcessInfo.processInfo.arguments.contains("-connectOnLaunch"), !app.auth.isSignedIn {
                Task { await app.auth.signIn() }
            }
            #endif
            // Re-fetch your display name each launch; it isn't saved.
            await app.auth.refreshIdentity()
        }
    }
}

/// Board, People, and Settings, each with its own navigation stack so bars come from the
/// system (they go vertical on iPhone Duo's outer display).
struct AppTabs: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab("Board", systemImage: "trophy", value: AppModel.Tab.board) {
                BoardView()
            }
            Tab("People", systemImage: "person.2", value: AppModel.Tab.people) {
                PeopleView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppModel.Tab.settings) {
                SettingsView()
            }
        }
    }
}
