import SwiftUI

/// Committed for iPhone. This shell compiles the Mac app's platform-neutral core (models,
/// ranking, persistence, the stores, and `StandingRow`) through shared target membership.
@main
struct CommitStandingsiOSApp: App {
    // Same durable snapshot as the Mac, so saved numbers render immediately on launch.
    @State private var store = StandingsStore(
        snapshotPersistence: UserDefaultsStandingsSnapshotPersistence(),
        hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence()
    )

    var body: some Scene {
        WindowGroup {
            PlaceholderBoardView(store: store)
        }
    }
}
