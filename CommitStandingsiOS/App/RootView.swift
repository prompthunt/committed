import SwiftUI

/// The app root: Board, People, and Settings tabs, each with its own `NavigationStack`, so the
/// system provides every bar (and moves them to the side on iPhone Duo). Connect GitHub covers
/// the tabs whenever no GitHub account is connected, including after Disconnect.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Board", systemImage: "trophy", value: AppTab.board) {
                BoardView()
            }
            Tab("People", systemImage: "person.2", value: AppTab.people) {
                PeopleView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .fullScreenCover(isPresented: .constant(model.needsConnect)) {
            ConnectGitHubView()
        }
        .onOpenURL { model.open($0) }
        .onChange(of: model.store.visibilityRevision) {
            Task { await model.visibilityDidChange() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: Task { await model.sceneDidBecomeActive() }
            case .background:
                model.sceneDidEnterBackground()
                if model.auth.isSignedIn { Task { await BackgroundRefresh.schedule() } }
            default: break
            }
        }
    }
}
