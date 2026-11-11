import Foundation
import Testing
@testable import CommitStandingsiOS

/// A roster the test can change between people syncs.
final class MutableRoster: @unchecked Sendable {
    var members: [String]
    init(_ members: [String]) { self.members = members }
}

/// Live rank with the Committed relay configured (phase 2), through the app model: the privacy
/// disclosure before first enablement, push-token activities with a phase 1 fallback, and when the
/// relay hears about changes.
@MainActor
struct LiveRankRelayLifecycleTests {
    let clock = TestClock()
    let activities = FakeLiveRankActivities()
    let relay = FakeLiveRankRelay()
    let preferences = InMemoryLiveRankPreferences()
    let roster = MutableRoster(["ada", "bo"])

    init() {
        relay.pushUpdates = .token
    }

    private func makeModel(signedIn: Bool = true, relay: (any LiveRankRegistrar)? = nil) -> AppModel {
        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [ApprovingGitHubProtocol.self]
            return URLSession(configuration: config)
        }()
        let clock = clock
        let roster = roster
        let services = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: signedIn ? "gho_test" : nil),
            contributions: FakeContributions(["me": 3, "ada": 5, "bo": 1, "cy": 9]),
            gitHubAuth: GitHubAuth(clientID: "test", session: session, sleep: { _ in }, now: { clock.now }),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: "me", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: roster.members),
                ], updatedAt: clock.now)
            },
            refreshInterval: 9_999,
            now: { clock.now }
        )
        return AppModel(
            services: services, backgroundTime: FakeBackgroundTime(),
            liveRankActivities: activities, liveRankPreferences: preferences, liveRankRelay: relay ?? self.relay
        )
    }

    private var registered: [LiveRankConfiguration] { relay.configurations.compactMap { $0 } }

    // MARK: Disclosure

    @Test func asksBeforeTheFirstEnableAndStaysOffMeanwhile() async {
        let model = makeModel()

        await model.sceneDidBecomeActive()

        #expect(model.isShowingLiveRankDisclosure)
        #expect(!model.liveRank.isEnabled)
        #expect(model.liveRank.status == .off)
        #expect(activities.running.isEmpty)
        #expect(registered.isEmpty)
    }

    @Test func acceptingTurnsLiveRankOnWithTheRelay() async {
        let model = makeModel()
        await model.sceneDidBecomeActive()

        await model.acceptLiveRankDisclosure()

        #expect(!model.isShowingLiveRankDisclosure)
        #expect(model.liveRank.isEnabled)
        #expect(activities.startedPushUpdates == [.token])
        #expect(registered == [LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada", "bo"], window: .daily)])
        #expect(preferences.load() == LiveRankPreferences(isEnabled: true, window: .daily, relayDisclosureAccepted: true))
    }

    @Test func theDisclosureAppearsOnlyOnce() async {
        let model = makeModel()
        await model.sceneDidBecomeActive()
        await model.acceptLiveRankDisclosure()
        await model.liveRankSwitchChanged(false)

        await model.liveRankSwitchChanged(true)
        let relaunched = makeModel()
        await relaunched.sceneDidBecomeActive()

        #expect(!model.isShowingLiveRankDisclosure)
        #expect(model.liveRank.isEnabled)
        #expect(!relaunched.isShowingLiveRankDisclosure)
    }

    @Test func decliningLeavesLiveRankOff() async {
        let model = makeModel()
        await model.sceneDidBecomeActive()

        await model.declineLiveRankDisclosure()

        #expect(!model.isShowingLiveRankDisclosure)
        #expect(!model.liveRank.isEnabled)
        #expect(activities.running.isEmpty)
        #expect(registered.isEmpty)
        // Not asked again on the next launch.
        let relaunched = makeModel()
        await relaunched.sceneDidBecomeActive()
        #expect(!relaunched.isShowingLiveRankDisclosure)
    }

    @Test func theSwitchAsksFirstAfterDeclining() async {
        let model = makeModel()
        await model.sceneDidBecomeActive()
        await model.declineLiveRankDisclosure()

        await model.liveRankSwitchChanged(true)

        #expect(model.isShowingLiveRankDisclosure)
        #expect(!model.liveRank.isEnabled)
        await model.acceptLiveRankDisclosure()
        #expect(model.liveRank.isEnabled)
        #expect(activities.running.count == 1)
    }

    @Test func notAskedUntilConnected() async {
        let model = makeModel(signedIn: false)
        await model.sceneDidBecomeActive()
        #expect(!model.isShowingLiveRankDisclosure)
    }

    @Test func phaseOneNeverAsks() async {
        relay.pushUpdates = .none
        let model = makeModel()

        await model.sceneDidBecomeActive()

        #expect(!model.isShowingLiveRankDisclosure)
        #expect(model.liveRank.isEnabled)
        #expect(activities.startedPushUpdates == [.none])
    }

    @Test func anEarlierOnWithoutTheDisclosureStillAsks() async {
        // Turned on in a phase 1 build; this build has a relay.
        preferences.save(LiveRankPreferences(isEnabled: true))
        let model = makeModel()

        await model.sceneDidBecomeActive()

        #expect(model.isShowingLiveRankDisclosure)
        #expect(registered.isEmpty)
    }

    @Test func savedPreferencesFromBeforeTheRelayStillLoad() throws {
        let old = Data(#"{"isEnabled":false,"window":"weekly"}"#.utf8)
        let decoded = try JSONDecoder().decode(LiveRankPreferences.self, from: old)
        #expect(decoded == LiveRankPreferences(isEnabled: false, window: .weekly, relayDisclosureAccepted: false))
    }

    // MARK: Push tokens

    @Test func fallsBackToPhaseOneWhenPushTokensAreRefused() async {
        preferences.save(LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true))
        activities.tokenStartError = CocoaError(.featureUnsupported)
        let model = makeModel()

        await model.sceneDidBecomeActive()

        #expect(activities.startedPushUpdates == [.none])
        #expect(model.liveRank.status == .live)
    }

    // MARK: A relay older than This month

    /// A relay that can't rank This month leaves Live rank to the app: the This month activity
    /// starts without a push token and the app keeps it up to date, as without a relay. The relay
    /// stays configured, so the disclosure isn't asked again.
    @Test func aRelayThatCannotRankTheWindowLeavesLiveRankToTheApp() async {
        preferences.save(LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true))
        relay.unservedWindows = [.month]
        let model = makeModel()
        await model.sceneDidBecomeActive()
        #expect(model.liveRank.isRelayKeepingCurrent)

        await model.setLiveRankWindow(.month)

        #expect(activities.startedPushUpdates == [.token, .none])
        #expect(activities.running.count == 1)
        #expect(activities.states.first?.window == "month")
        #expect(model.liveRank.status == .live)
        #expect(!model.liveRank.isRelayKeepingCurrent)
        #expect(model.liveRank.isRelayConfigured)
        #expect(model.liveRank.isEnabled)
    }

    /// End to end with the relay client: an older relay answers `invalid_window` to This month. The
    /// app takes its registration back, starts the activity without a push token, and keeps it
    /// current on its own refreshes, never asking the relay again in this launch.
    @Test func anOlderRelayFallsBackToTheAppCleanly() async {
        preferences.save(LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true))
        let api = FakeRelayAPI()
        let registrar = RelayLiveRankRegistrar(
            api: api, installations: InMemoryRelayInstallationStore(), apnsEnvironment: .sandbox,
            timeZone: { TimeZone(identifier: "UTC")! }, notificationCenter: NotificationCenter()
        )
        api.rejectedWindows = ["month"]
        let model = makeModel(relay: registrar)
        await model.sceneDidBecomeActive()
        #expect(api.registrations.map(\.window) == ["daily"])

        await model.setLiveRankWindow(.month)

        #expect(api.calls.last == .unregister)
        #expect(activities.startedPushUpdates == [.token, .none])
        #expect(activities.states.first?.window == "month")
        #expect(model.liveRank.status == .live)

        let attempts = api.registerAttempts
        clock.advance(300)
        await model.pullToRefresh()
        await model.sceneDidBecomeActive()
        await model.backgroundRefresh()

        #expect(api.registerAttempts == attempts)
        #expect(activities.states.first?.updatedAt == Int(clock.now.timeIntervalSince1970))
    }

    // MARK: Re-registration

    @Test func aPeopleSyncThatChangesTheRosterReRegisters() async {
        preferences.save(LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true))
        let model = makeModel()
        await model.sceneDidBecomeActive()

        roster.members = ["ada", "bo", "cy"]
        clock.advance(300)
        await model.pullToRefresh()
        clock.advance(300)
        await model.pullToRefresh()            // same people again: nothing new

        #expect(registered.count == 2)
        #expect(Set(registered.last?.competitors ?? []) == ["me", "ada", "bo", "cy"])
    }

    @Test func pendingRelayWorkIsRetriedOnOpenAndInBackgroundRefresh() async {
        preferences.save(LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true))
        let model = makeModel()

        await model.sceneDidBecomeActive()
        await model.backgroundRefresh()

        #expect(relay.retries == 2)
    }

    @Test func disconnectUnregisters() async {
        preferences.save(LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true))
        let model = makeModel()
        await model.sceneDidBecomeActive()

        model.auth.signOut()
        await model.liveRank.idle()

        #expect(relay.configurations.last == .some(nil))
    }
}
