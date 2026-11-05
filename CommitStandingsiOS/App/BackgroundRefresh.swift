import BackgroundTasks
import Foundation

/// Background app refresh: iOS wakes Committed now and then to refresh people and Contributions,
/// which also updates Live rank. iOS decides when, so this is opportunistic; the Committed relay
/// (#45) is what keeps Live rank current with the app closed. The handler is the scene's
/// `.backgroundTask(.appRefresh(_:))` in `CommittedApp`; the identifier is listed under
/// `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
enum BackgroundRefresh {
    static let identifier = "com.addisonk.CommitStandings.iOS.refresh"

    /// Ask for the next refresh, no sooner than 15 minutes from now. Submitting again replaces the
    /// pending request.
    @MainActor
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
