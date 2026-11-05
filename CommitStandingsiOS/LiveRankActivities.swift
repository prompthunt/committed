import ActivityKit
import Foundation

/// A Live rank activity as the lifecycle sees it.
struct LiveRankActivity: Equatable {
    let id: String
    let selfLogin: String
    let state: LiveRankState
}

/// The small surface of ActivityKit that Live rank's lifecycle needs, so the rules in
/// `LiveRankController` are tested with a fake. Every write carries the state's stale date
/// (20 minutes after its data).
@MainActor
protocol LiveRankActivities: AnyObject {
    /// Whether iOS allows Committed's Live Activities (Settings ▸ Committed ▸ Live Activities).
    var areActivitiesEnabled: Bool { get }
    /// Live rank activities still on screen (active or stale), oldest first. Ended and
    /// dismissed ones (including iOS's 8-hour cutoff) are left out.
    func current() -> [LiveRankActivity]
    /// Request a new activity. Fails in the background, and when iOS disallows it.
    func start(selfLogin: String, state: LiveRankState) throws -> LiveRankActivity
    func update(id: String, to state: LiveRankState) async
    /// End and dismiss right away.
    func end(id: String) async
}

/// For the unit-test host and anything else that must never show a Live Activity.
@MainActor
final class NoLiveRankActivities: LiveRankActivities {
    var areActivitiesEnabled: Bool { false }
    func current() -> [LiveRankActivity] { [] }
    func start(selfLogin: String, state: LiveRankState) throws -> LiveRankActivity {
        throw CocoaError(.featureUnsupported)
    }
    func update(id: String, to state: LiveRankState) async {}
    func end(id: String) async {}
}

/// The real thing, and the only file that touches ActivityKit. Phase 1 starts activities
/// without a push token; the relay (#45) passes `.token` and observes the tokens.
@MainActor
final class ActivityKitLiveRankActivities: LiveRankActivities {
    private let pushType: PushType?

    /// `pushType: .token` lets APNs (or `xcrun simctl push` in the simulator) update the activity.
    init(pushType: PushType? = nil) {
        self.pushType = pushType
    }

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func current() -> [LiveRankActivity] {
        Activity<LiveRankAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .map(Self.snapshot)
    }

    func start(selfLogin: String, state: LiveRankState) throws -> LiveRankActivity {
        let activity = try Activity.request(
            attributes: LiveRankAttributes(selfLogin: selfLogin),
            content: Self.content(state),
            pushType: pushType
        )
        return Self.snapshot(activity)
    }

    func update(id: String, to state: LiveRankState) async {
        await Self.update(id: id, content: Self.content(state))
    }

    func end(id: String) async {
        await Self.end(id: id)
    }

    // `Activity` isn't Sendable: look it up and use it off the main actor, in one place.
    private nonisolated static func update(id: String, content: ActivityContent<LiveRankState>) async {
        await Activity<LiveRankAttributes>.activities.first { $0.id == id }?.update(content)
    }

    private nonisolated static func end(id: String) async {
        await Activity<LiveRankAttributes>.activities.first { $0.id == id }?.end(nil, dismissalPolicy: .immediate)
    }

    private static func content(_ state: LiveRankState) -> ActivityContent<LiveRankState> {
        ActivityContent(state: state, staleDate: state.staleDate)
    }

    private static func snapshot(_ activity: Activity<LiveRankAttributes>) -> LiveRankActivity {
        LiveRankActivity(id: activity.id, selfLogin: activity.attributes.selfLogin, state: activity.content.state)
    }
}
