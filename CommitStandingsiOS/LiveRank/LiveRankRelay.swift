import Foundation

/// What the Committed relay needs to keep Live rank current with the app closed: who you are,
/// who's visible on your board (in board order, for tie-breaks), and Live rank's Window.
struct LiveRankConfiguration: Equatable, Sendable {
    var selfLogin: String
    var competitors: [String]
    var window: ContributionWindow
}

/// The seam for the Committed relay (#45). `LiveRankController` calls it whenever the
/// configuration changes, and with nil when Live rank turns off or GitHub disconnects
/// (unregister). Calls are de-duplicated, so a refresh that changes nothing sends nothing.
@MainActor
protocol LiveRankRegistrar: AnyObject {
    /// `.token` once a relay is configured, so new activities get a push token.
    var pushUpdates: LiveRankPushUpdates { get }
    func liveRankDidChange(_ configuration: LiveRankConfiguration?) async
}

/// Phase 1: no relay. Live rank updates only when the app refreshes.
@MainActor
final class NoLiveRankRelay: LiveRankRegistrar {
    var pushUpdates: LiveRankPushUpdates { .none }
    func liveRankDidChange(_ configuration: LiveRankConfiguration?) async {}
}
