import SwiftUI

/// The app root: Board, People, and Settings tabs, each with its own `NavigationStack`, so the
/// system provides every bar (and moves them to the side on iPhone Duo). Connect GitHub covers
/// the tabs whenever no GitHub account is connected, including after Disconnect.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// Lets the square fields rest after a while without a touch.
    @State private var interactions = InteractionClock()

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
        // The marketing site's world: ink, lime, Inter Tight, dark only (also UIUserInterfaceStyle
        // in Info.plist, so launch and system sheets match). Set here so every host of the root,
        // including the render tests, gets it.
        .environment(\.standingRowStyle, .committed)
        .tint(.lime)
        .background(Color.ink)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: .constant(model.needsConnect)) {
            ConnectGitHubView()
        }
        // What the Committed relay receives, before Live rank first turns on (only with a relay).
        .sheet(isPresented: $model.isShowingLiveRankDisclosure) {
            LiveRankDisclosureView()
        }
        .onOpenURL { model.open($0) }
        // Last, so the Connect cover and the disclosure sheet get them too.
        .environment(\.avatarFallbackStyle, .committed)
        .environment(interactions)
        .background { InteractionClockInstaller(clock: interactions) }
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
