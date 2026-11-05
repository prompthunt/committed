import SwiftUI

@main
struct CommittedApp: App {
    // Same durable snapshot and visibility storage as the Mac app, so the board shows saved
    // numbers on launch. Nothing writes them yet on iPhone; until it does, the board is the sample.
    @State private var store = StandingsStore(
        snapshotPersistence: UserDefaultsStandingsSnapshotPersistence(),
        hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence()
    )

    var body: some Scene {
        WindowGroup {
            PlaceholderBoardView()
                .environment(store)
        }
    }
}
