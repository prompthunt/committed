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

/// The real thing, over `Activity<LiveRankAttributes>`. The relay's token streams are in
/// `ActivityKitLiveRankTokens`.
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

/// ActivityKit's push tokens, handed to the relay client as they arrive: the push-to-start token,
/// and the push token of every Live rank activity, including ones the relay started by
/// push-to-start. Started at app launch, background launches included, so a relay-started activity
/// is reported promptly (the relay counts its age from the report).
@MainActor
final class ActivityKitLiveRankTokens {
    private let receiver: any LiveRankTokenReceiving
    private var observed: Set<String> = []
    private var tasks: [Task<Void, Never>] = []

    init(receiver: any LiveRankTokenReceiving) {
        self.receiver = receiver
    }

    func start() {
        guard tasks.isEmpty else { return }
        let receiver = receiver
        tasks.append(Task {
            for await token in Activity<LiveRankAttributes>.pushToStartTokenUpdates {
                LiveRankLog.relay.info("push-to-start token \(token.lowercaseHex.prefix(8), privacy: .public)…")
                await receiver.pushToStartTokenDidChange(token)
            }
        })
        for activity in Activity<LiveRankAttributes>.activities { observe(activity) }
        tasks.append(Task { [weak self] in
            for await activity in Activity<LiveRankAttributes>.activityUpdates {
                self?.observe(activity)
            }
        })
    }

    private func observe(_ activity: Activity<LiveRankAttributes>) {
        guard observed.insert(activity.id).inserted else { return }
        let id = activity.id
        let receiver = receiver
        LiveRankLog.relay.info("observing activity \(id, privacy: .public)")
        tasks.append(Task {
            for await token in activity.pushTokenUpdates {
                LiveRankLog.relay.info("activity \(id, privacy: .public) push token \(token.lowercaseHex.prefix(8), privacy: .public)…")
                await receiver.activityPushTokenDidChange(activityID: id, token: token)
            }
        })
    }
}
