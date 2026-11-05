import ActivityKit
import Foundation

/// A Live rank activity as the lifecycle sees it.
struct LiveRankActivity: Equatable, Sendable {
    let id: String
    let selfLogin: String
    let state: LiveRankState
}

/// How a new activity gets updates besides the app's own: `.none` in phase 1, `.token` once the
/// Committed relay (#45) pushes them.
enum LiveRankPushUpdates: Equatable, Sendable {
    case none
    case token
}

/// The small surface of ActivityKit that Live rank's lifecycle needs, so `LiveRankController`'s
/// rules are tested with a fake. Every write carries the state's stale date (20 minutes after its
/// data).
@MainActor
protocol LiveRankActivities: AnyObject {
    /// Whether iOS allows Committed's Live Activities (Settings ▸ Committed ▸ Live Activities).
    var areActivitiesEnabled: Bool { get }
    /// Live rank activities still on screen (active or stale), oldest first.
    func current() -> [LiveRankActivity]
    /// Request a new activity. iOS refuses in the background and when Live Activities are off.
    func start(_ attributes: LiveRankAttributes, state: LiveRankState, pushUpdates: LiveRankPushUpdates) throws
        -> LiveRankActivity
    func update(id: String, to state: LiveRankState) async
    /// End and dismiss right away.
    func end(id: String) async
}

/// For the unit-test host and anything else that must never show a Live Activity.
@MainActor
final class NoLiveRankActivities: LiveRankActivities {
    var areActivitiesEnabled: Bool { false }
    func current() -> [LiveRankActivity] { [] }
    func start(_ attributes: LiveRankAttributes, state: LiveRankState, pushUpdates: LiveRankPushUpdates) throws
        -> LiveRankActivity {
        throw CocoaError(.featureUnsupported)
    }
    func update(id: String, to state: LiveRankState) async {}
    func end(id: String) async {}
}

/// The real thing, over `Activity<LiveRankAttributes>`.
///
/// #45 adds the relay's token streams here, next to these methods: `Activity<LiveRankAttributes>
/// .pushToStartTokenUpdates`, `.activityUpdates` (relay-started activities), and each activity's
/// `pushTokenUpdates`. See the spec #39 notes, `43-live-rank.md`.
@MainActor
final class ActivityKitLiveRankActivities: LiveRankActivities {
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func current() -> [LiveRankActivity] {
        Activity<LiveRankAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .map(Self.snapshot)
    }

    func start(_ attributes: LiveRankAttributes, state: LiveRankState, pushUpdates: LiveRankPushUpdates) throws
        -> LiveRankActivity {
        let activity = try Activity.request(
            attributes: attributes,
            content: Self.content(state),
            pushType: pushUpdates == .token ? .token : nil
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
