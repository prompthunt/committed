import ActivityKit
import Foundation

/// A Live rank activity as the lifecycle sees it.
struct LiveRankActivity: Equatable {
    let id: String
    let selfLogin: String
    let state: LiveRankState
}

/// A push token ActivityKit issued, for the Committed relay.
enum LiveRankPushToken: Equatable, Sendable {
    /// Lets the relay start a new Live rank activity (push-to-start). Changes now and then.
    case pushToStart(Data)
    /// Lets the relay update this activity, including one the relay started itself.
    case activity(id: String, token: Data)
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
    /// Start delivering push tokens: the push-to-start token, and the token of every activity,
    /// those already running and any started later (by the app or by a push). Only called when
    /// a relay is configured.
    func observePushTokens(_ handler: @escaping @MainActor (LiveRankPushToken) -> Void)
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
    func observePushTokens(_ handler: @escaping @MainActor (LiveRankPushToken) -> Void) {}
}

/// The real thing, and the only file that touches ActivityKit. Phase 1 starts activities
/// without a push token; with a relay, `AppDependencies.live()` passes `.token` and Live rank
/// observes the tokens.
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

    private var observing = false
    private var observedActivityIDs: Set<String> = []
    private var tokenHandler: (@MainActor (LiveRankPushToken) -> Void)?

    func observePushTokens(_ handler: @escaping @MainActor (LiveRankPushToken) -> Void) {
        tokenHandler = handler
        guard !observing else { return }
        observing = true
        Task { [weak self] in
            for await token in Activity<LiveRankAttributes>.pushToStartTokenUpdates {
                self?.tokenHandler?(.pushToStart(token))
            }
        }
        // `activityUpdates` reports activities started from now on (including by push-to-start),
        // not ones already running, so those are observed here first.
        for activity in Activity<LiveRankAttributes>.activities { observeToken(of: activity) }
        Task { [weak self] in
            for await activity in Activity<LiveRankAttributes>.activityUpdates {
                self?.observeToken(of: activity)
            }
        }
    }

    private func observeToken(of activity: Activity<LiveRankAttributes>) {
        let id = activity.id
        guard observedActivityIDs.insert(id).inserted else { return }
        Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                self?.tokenHandler?(.activity(id: id, token: token))
            }
        }
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
