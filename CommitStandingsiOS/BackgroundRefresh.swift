import BackgroundTasks
import Foundation

/// iOS background app refresh. iOS decides when it actually runs; Committed asks for one about
/// every 15 minutes while it's in the background, so Live rank keeps up with the app closed.
enum BackgroundRefresh {
    /// Also listed in Info.plist's `BGTaskSchedulerPermittedIdentifiers`.
    static let identifier = "com.addisonk.CommitStandings.iOS.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
