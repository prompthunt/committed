import Foundation
import Testing
@testable import CommitStandingsiOS

/// ActivityKit as Live rank sees it, in memory.
@MainActor
final class FakeLiveRankActivities: LiveRankActivities {
    var areActivitiesEnabled = true
    /// Activities on screen, oldest first.
    private(set) var running: [LiveRankActivity] = []
    private(set) var log: [String] = []
    private(set) var startedPushUpdates: [LiveRankPushUpdates] = []
    var startError: (any Error)?
    /// Fails only push-token requests, like a build without the Push Notifications entitlement.
    var tokenStartError: (any Error)?
    private var next = 0

    func current() -> [LiveRankActivity] { running }

    /// An activity left over from an earlier launch.
    func leftOver(selfLogin: String, window: ContributionWindow, rank: Int? = nil) {
        next += 1
        running.append(LiveRankActivity(
            id: "old-\(next)", selfLogin: selfLogin,
            state: LiveRankState(window: window.rawValue, rank: rank, competitorCount: 2, contributions: nil,
                                 above: nil, below: nil, movementToday: 0, updatedAt: 0)
        ))
    }

    func start(_ attributes: LiveRankAttributes, state: LiveRankState, pushUpdates: LiveRankPushUpdates) throws
        -> LiveRankActivity {
        if let startError { throw startError }
        if pushUpdates == .token, let tokenStartError { throw tokenStartError }
        next += 1
        let activity = LiveRankActivity(id: "a\(next)", selfLogin: attributes.selfLogin, state: state)
        running.append(activity)
        startedPushUpdates.append(pushUpdates)
        log.append("start \(activity.id) \(state.window)")
        return activity
    }

    func update(id: String, to state: LiveRankState) async {
        guard let index = running.firstIndex(where: { $0.id == id }) else { return }
        running[index] = LiveRankActivity(id: id, selfLogin: running[index].selfLogin, state: state)
        log.append("update \(id)")
    }

    func end(id: String) async {
        running.removeAll { $0.id == id }
        log.append("end \(id)")
    }

    var states: [LiveRankState] { running.map(\.state) }
}

/// What the Committed relay would be told (#45), without a relay.
@MainActor
final class FakeLiveRankRelay: LiveRankRegistrar {
    var pushUpdates: LiveRankPushUpdates = .none
    private(set) var configurations: [LiveRankConfiguration?] = []
    private(set) var retries = 0
    func liveRankDidChange(_ configuration: LiveRankConfiguration?) async {
        configurations.append(configuration)
    }
    func retryPendingWork() async {
        retries += 1
    }
}

/// Approves the device flow straight away.
final class ApprovingGitHubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = switch request.url?.path {
        case "/login/device/code":
            #"{"device_code":"d","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
        case "/user": #"{"login":"me","name":"Me"}"#
        default: #"{"access_token":"gho_new"}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Live rank's phase 1 lifecycle, through the app model: start in the foreground once connected,
/// update only on change, end on Disconnect or off, end and restart on a Window change, and clear
/// out stray activities.
@MainActor
struct LiveRankLifecycleTests {
    let clock = TestClock()
    let activities = FakeLiveRankActivities()
    let relay = FakeLiveRankRelay()
    let preferences = InMemoryLiveRankPreferences()

    private func makeModel(signedIn: Bool = true, counts: [String: Int] = ["me": 3, "ada": 5, "bo": 1])
        -> (AppModel, FakeContributions) {
        let contributions = FakeContributions(counts)
        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [ApprovingGitHubProtocol.self]
            return URLSession(configuration: config)
        }()
        let clock = clock
        let services = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: signedIn ? "gho_test" : nil),
            contributions: contributions,
            gitHubAuth: GitHubAuth(clientID: "test", session: session, sleep: { _ in }, now: { clock.now }),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: "me", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["ada", "bo"]),
                ], updatedAt: clock.now)
            },
            refreshInterval: 9_999,
            now: { clock.now }
        )
        let model = AppModel(
            services: services, backgroundTime: FakeBackgroundTime(),
            liveRankActivities: activities, liveRankPreferences: preferences, liveRankRelay: relay
        )
        return (model, contributions)
    }

    // MARK: Starting

    @Test func startsInTheForegroundOnceTheBoardLoads() async {
        let (model, _) = makeModel()

        await model.sceneDidBecomeActive()

        #expect(activities.running.count == 1)
        #expect(activities.running.first?.selfLogin == "me")
        #expect(activities.states.first?.rank == 2)
        #expect(activities.states.first?.above == .init(login: "ada", contributions: 5))
        #expect(model.liveRank.status == .live)
    }

    @Test func startsAfterConnectGitHub() async {
        let (model, _) = makeModel(signedIn: false)
        await model.sceneDidBecomeActive()
        #expect(activities.running.isEmpty)

        await model.connectGitHub()

        #expect(activities.running.map(\.selfLogin) == ["me"])
        #expect(activities.states.first?.contributions == 3)
    }

    @Test func doesNotStartInTheBackground() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        let started = activities.running.first?.id
        await activities.end(id: started!)          // e.g. iOS's 8-hour limit
        model.sceneDidEnterBackground()

        await model.backgroundRefresh()

        #expect(activities.running.isEmpty)
        #expect(model.liveRank.status == .waiting)
    }

    @Test func respectsLiveActivitiesOffInIOSSettings() async {
        activities.areActivitiesEnabled = false
        let (model, contributions) = makeModel()

        await model.sceneDidBecomeActive()

        #expect(activities.running.isEmpty)
        #expect(model.liveRank.status == .disabledInSystem)
        // Nothing extra fetched for an activity nobody can see.
        #expect(await contributions.windows.allSatisfy { $0 == .daily })
    }

    @Test func reportsAStartFailure() async {
        activities.startError = CocoaError(.featureUnsupported)
        let (model, _) = makeModel()

        await model.sceneDidBecomeActive()

        guard case .failed = model.liveRank.status else {
            Issue.record("expected a failure, got \(model.liveRank.status)"); return
        }
    }

    @Test func phaseOneStartsWithoutPushUpdates() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        #expect(activities.startedPushUpdates == [.none])
    }

    // MARK: Updating

    @Test func updatesOnlyWhenTheStateChanged() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        model.sceneDidEnterBackground()
        clock.advance(30)

        await model.sceneDidBecomeActive()          // fresh data: no refresh, nothing new to show
        #expect(activities.log.filter { $0.hasPrefix("update") }.isEmpty)

        clock.advance(300)
        await model.pullToRefresh()                 // newer data
        #expect(activities.log.filter { $0.hasPrefix("update") }.count == 1)
        #expect(activities.running.count == 1)
    }

    @Test func backgroundRefreshUpdatesTheActivity() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        model.sceneDidEnterBackground()
        clock.advance(600)

        await model.backgroundRefresh()

        #expect(activities.states.first?.updatedAt == Int(clock.now.timeIntervalSince1970))
        #expect(activities.log.filter { $0.hasPrefix("start") }.count == 1)
    }

    @Test func hidingSomeoneUpdatesRightAwayInTheForeground() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()

        model.store.setHidden(true, username: "ada")
        await model.visibilityDidChange()

        #expect(activities.states.first?.rank == 1)
        #expect(activities.states.first?.competitorCount == 2)
        #expect(activities.states.first?.above == nil)
    }

    @Test func liveRankFollowsItsOwnWindowNotTheBoards() async {
        preferences.save(LiveRankPreferences(isEnabled: true, window: .weekly))
        let (model, contributions) = makeModel()

        await model.sceneDidBecomeActive()

        #expect(activities.states.first?.window == "weekly")
        #expect(activities.states.first?.contributions == 3)
        #expect(await contributions.windows.filter { $0 == .weekly }.count == 3)
        #expect(model.store.selectedWindow == .daily)
    }

    // MARK: Window, off, Disconnect

    @Test func changingTheWindowEndsAndRestarts() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        let first = activities.running.first!.id

        await model.setLiveRankWindow(.monthly)

        #expect(activities.log.contains("end \(first)"))
        #expect(activities.running.count == 1)
        #expect(activities.states.first?.window == "monthly")
        #expect(activities.states.first?.contributions == 3)
        #expect(preferences.load().window == .monthly)
    }

    @Test func turningOffEndsItAndTurningOnStartsAgain() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()

        await model.setLiveRankEnabled(false)
        #expect(activities.running.isEmpty)
        #expect(model.liveRank.status == .off)
        #expect(preferences.load().isEnabled == false)

        clock.advance(30)
        await model.pullToRefresh()
        #expect(activities.running.isEmpty)

        await model.setLiveRankEnabled(true)
        #expect(activities.running.count == 1)
    }

    @Test func staysOffAcrossLaunches() async {
        preferences.save(LiveRankPreferences(isEnabled: false, window: .daily))
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        #expect(activities.running.isEmpty)
        #expect(model.liveRank.status == .off)
    }

    @Test func disconnectEndsIt() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()

        model.auth.signOut()
        await model.liveRank.idle()

        #expect(activities.running.isEmpty)
        #expect(relay.configurations.last == .some(nil))
    }

    // MARK: Strays

    @Test func duplicatesAreEndedOnLaunch() async {
        activities.leftOver(selfLogin: "me", window: .daily)
        activities.leftOver(selfLogin: "me", window: .daily)
        activities.leftOver(selfLogin: "me", window: .weekly)
        activities.leftOver(selfLogin: "someone-else", window: .daily)
        let (model, _) = makeModel()

        await model.sceneDidBecomeActive()

        #expect(activities.running.map(\.id) == ["old-1"])
        #expect(activities.states.first?.rank == 2)   // kept and brought up to date
        #expect(!activities.log.contains { $0.hasPrefix("start") })
    }

    @Test func strayActivitiesEndWhenSignedOut() async {
        activities.leftOver(selfLogin: "me", window: .daily)
        let (model, _) = makeModel(signedIn: false)

        await model.sceneDidBecomeActive()

        #expect(activities.running.isEmpty)
    }

    // MARK: Relay seam (#45)

    @Test func relayHearsAboutEachChangeOnce() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        clock.advance(300)
        await model.pullToRefresh()                    // same people, same Window: no news
        model.store.setHidden(true, username: "bo")
        await model.visibilityDidChange()
        await model.setLiveRankWindow(.weekly)
        await model.setLiveRankEnabled(false)

        #expect(relay.configurations == [
            LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada", "bo"], window: .daily),
            LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada"], window: .daily),
            LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada"], window: .weekly),
            nil,
        ])
    }

    @Test func relayDecidesWhetherActivitiesTakePushUpdates() async {
        relay.pushUpdates = .token
        preferences.save(LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true))
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        #expect(activities.startedPushUpdates == [.token])
    }
}
