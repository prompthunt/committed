import Testing
import Foundation
@testable import CommitStandingsiOS

/// The Committed relay as the app sees it, in memory: records every call and fails on request.
final class FakeRelayClient: LiveRankRelayClient, @unchecked Sendable {
    enum Call: Equatable {
        case register(RelayRegistration, install: String)
        case activity(id: String, token: String, startedAt: Int?, install: String)
        case unregister(install: String)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _failures: [RelayClientError] = []

    var calls: [Call] { lock.withLock { _calls } }
    var registrations: [RelayRegistration] {
        calls.compactMap { if case .register(let registration, _) = $0 { registration } else { nil } }
    }
    var lastRegistration: RelayRegistration? { registrations.last }
    var reportedActivities: [String] {
        calls.compactMap { if case .activity(let id, let token, _, _) = $0 { "\(id):\(token)" } else { nil } }
    }
    /// The start time sent with each activity report (nil when the app didn't start it).
    var reportedStarts: [Int?] {
        calls.compactMap { if case .activity(_, _, let startedAt, _) = $0 { .some(startedAt) } else { nil } }
    }
    var unregisterCount: Int {
        calls.filter { if case .unregister = $0 { true } else { false } }.count
    }

    /// The next calls fail with these errors, in order (and aren't recorded as delivered).
    func failNext(_ errors: RelayClientError...) { lock.withLock { _failures += errors } }
    func reset() { lock.withLock { _calls = [] } }

    func register(_ registration: RelayRegistration, as installation: RelayInstallation) async throws {
        try record(.register(registration, install: installation.id))
    }

    func reportActivity(id: String, pushToken: String, startedAt: Int?, as installation: RelayInstallation) async throws {
        try record(.activity(id: id, token: pushToken, startedAt: startedAt, install: installation.id))
    }

    func unregister(_ installation: RelayInstallation) async throws {
        try record(.unregister(install: installation.id))
    }

    private func record(_ call: Call) throws {
        try lock.withLock {
            if !_failures.isEmpty { throw _failures.removeFirst() }
            _calls.append(call)
        }
    }
}

/// Live rank with the Committed relay (phase 2): the disclosure, registration, and unregistration.
extension FakeGitHubSuites {
@Suite
@MainActor
struct LiveRankRelayTests {

    private struct Harness {
        let app: AppModel
        let activities: FakeLiveRankActivities
        let relay: FakeRelayClient
        let relayStore: InMemoryLiveRankRelayStore
        let persistence: InMemoryLiveRankPersistence
        let contributions: StubContributions
        let clock: TestClock
        let timeZone: TimeZoneBox
        let dependencies: AppDependencies
    }

    final class TimeZoneBox: @unchecked Sendable {
        var zone = TimeZone(identifier: "America/Los_Angeles")!
    }

    /// Connected as "me" with alice and bob on the board, a relay configured, not yet refreshed.
    private func connected(
        preferences: LiveRankPreferences = LiveRankPreferences(),
        activities: FakeLiveRankActivities = FakeLiveRankActivities(),
        relayStore: InMemoryLiveRankRelayStore = InMemoryLiveRankRelayStore(),
        persistence: InMemoryLiveRankPersistence? = nil,
        relay: FakeRelayClient = FakeRelayClient()
    ) -> Harness {
        FakeGitHub.reset(.init(login: "me", following: ["alice", "bob"]))
        let clock = TestClock()
        let contributions = StubContributions(["me": 5, "alice": 9, "bob": 3])
        let timeZone = TimeZoneBox()
        let persistence = persistence ?? InMemoryLiveRankPersistence(preferences)
        var dependencies = AppDependencies.testing(
            contributions: contributions,
            credentials: InMemoryGitHubCredentialStore(token: "gho_test"),
            clock: clock
        )
        dependencies.makeLiveRankActivities = { activities }
        dependencies.liveRankPersistence = persistence
        dependencies.relay = LiveRankRelayDependencies(client: relay, store: relayStore, environment: "sandbox")
        dependencies.timeZone = { timeZone.zone }
        return Harness(app: AppModel(dependencies), activities: activities, relay: relay, relayStore: relayStore,
                       persistence: persistence, contributions: contributions, clock: clock, timeZone: timeZone,
                       dependencies: dependencies)
    }

    /// Connected, with the disclosure already accepted and the first activity running.
    private func live(relayStore: InMemoryLiveRankRelayStore = InMemoryLiveRankRelayStore()) async -> Harness {
        let h = connected(preferences: LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true),
                          relayStore: relayStore)
        await h.app.sceneDidBecomeActive()
        await h.app.liveRank.idle()
        return h
    }

    // MARK: - Disclosure

    @Test func withARelayNothingStartsOrRegistersUntilTheDisclosureIsAccepted() async throws {
        let h = connected()

        await h.app.sceneDidBecomeActive()

        #expect(h.app.liveRank.isPresentingDisclosure, "asked once the board is here")
        #expect(h.app.liveRank.isEnabled == false)
        #expect(h.activities.activities.isEmpty)
        #expect(h.relay.calls.isEmpty)

        await h.app.acceptLiveRankDisclosure()

        #expect(h.app.liveRank.isPresentingDisclosure == false)
        #expect(h.app.liveRank.isEnabled)
        #expect(h.activities.only?.state.rank == 2)
        let registration = try #require(h.relay.lastRegistration)
        #expect(registration == RelayRegistration(
            board: RelayBoard(login: "me", competitors: ["me", "alice", "bob"], window: "daily",
                              timeZone: "America/Los_Angeles"),
            environment: "sandbox", pushToStartToken: nil
        ))
        #expect(h.persistence.loadPreferences() == LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true))
    }

    @Test func decliningLeavesLiveRankOffAndDoesNotAskAgainOnItsOwn() async throws {
        let h = connected()
        await h.app.sceneDidBecomeActive()

        h.app.declineLiveRankDisclosure()
        await h.app.liveRank.idle()

        #expect(h.app.liveRank.isPresentingDisclosure == false)
        #expect(h.app.liveRank.isEnabled == false)
        #expect(h.app.liveRank.status == .off)
        #expect(h.activities.activities.isEmpty)
        #expect(h.relay.calls.isEmpty)

        h.clock.advance(600)
        await h.app.sceneDidBecomeActive()
        #expect(h.app.liveRank.isPresentingDisclosure == false, "declined is a decision: no asking every launch")

        await h.app.setLiveRankEnabled(true)
        #expect(h.app.liveRank.isPresentingDisclosure, "turning it on later still shows the disclosure first")
        #expect(h.app.liveRank.isEnabled == false)
        #expect(h.relay.calls.isEmpty)
    }

    @Test func onceAcceptedTheSwitchNeverAsksAgain() async throws {
        let h = await live()
        await h.app.setLiveRankEnabled(false)
        await h.app.liveRank.idle()

        await h.app.setLiveRankEnabled(true)
        await h.app.liveRank.idle()

        #expect(h.app.liveRank.isPresentingDisclosure == false)
        #expect(h.app.liveRank.isEnabled)
        #expect(h.activities.only != nil)
    }

    @Test func withoutARelayLiveRankIsOnWithoutAsking() async throws {
        FakeGitHub.reset(.init(login: "me", following: ["alice"]))
        let activities = FakeLiveRankActivities()
        var dependencies = AppDependencies.testing(
            contributions: StubContributions(["me": 1, "alice": 2]),
            credentials: InMemoryGitHubCredentialStore(token: "gho_test")
        )
        dependencies.makeLiveRankActivities = { activities }

        let app = AppModel(dependencies)
        await app.sceneDidBecomeActive()

        #expect(app.liveRank.isPresentingDisclosure == false)
        #expect(app.liveRank.isEnabled)
        #expect(activities.only != nil)
        #expect(activities.observingPushTokens == false, "phase 1 doesn't ask ActivityKit for push tokens")
    }

    // MARK: - Push tokens

    @Test func theActivityAndPushToStartTokensAreReported() async throws {
        let h = await live()
        let id = try #require(h.activities.only?.id)
        #expect(h.activities.observingPushTokens)

        h.activities.issue(.activity(id: id, token: Data([0xab, 0xcd])))
        await h.app.liveRank.idle()
        #expect(h.relay.reportedActivities == ["\(id):abcd"])

        h.activities.issue(.pushToStart(Data([0x01, 0x02])))
        await h.app.liveRank.idle()
        #expect(h.relay.lastRegistration?.pushToStartToken == "0102", "a new push-to-start token re-registers")

        h.activities.issue(.activity(id: id, token: Data([0xab, 0xcd])))
        await h.app.liveRank.idle()
        #expect(h.relay.reportedActivities.count == 1, "the same token isn't sent twice")
    }

    @Test func anActivityTheAppStartedIsReportedWithItsStartTime() async throws {
        let h = await live()  // started now
        let started = Int(h.clock.date.timeIntervalSince1970)
        let id = try #require(h.activities.only?.id)

        h.clock.advance(3600)  // its token only arrives an hour later
        h.activities.issue(.activity(id: id, token: Data([0x0a])))
        await h.app.liveRank.idle()

        #expect(h.relay.reportedActivities == ["\(id):0a"])
        #expect(h.relay.reportedStarts == [started], "the relay ages it from its start, not from the report")
    }

    @Test func anActivityTheRelayStartedIsKeptAndItsTokenReportedInTheBackground() async throws {
        let h = await live()
        let first = try #require(h.activities.only)
        h.app.sceneDidEnterBackground()
        // iOS ends the first one at its 8-hour limit; the relay starts a fresh one.
        h.activities.systemEnds(id: first.id)
        let pushed = h.activities.startedByPush(selfLogin: "me", state: first.state)

        h.activities.issue(.activity(id: pushed.id, token: Data([0x0f])))
        await h.app.liveRank.idle()

        #expect(h.relay.reportedActivities.last == "\(pushed.id):0f")
        #expect(h.relay.reportedStarts.last == .some(nil), "the relay knows when it sent the start")
        #expect(h.activities.ended.isEmpty, "the relay's activity is Live rank's, not a stray")
        #expect(h.activities.started == 1, "no second activity next to it")
        #expect(h.activities.only?.id == pushed.id)
    }

    @Test func aTokenArrivingBeforeTheBoardCanBeReadIsStillReportedAndNothingEnds() async throws {
        // A background launch for a relay-started activity before first unlock: the GitHub
        // token can't be read, so the app looks signed out.
        let relayStore = InMemoryLiveRankRelayStore()
        let h = await live(relayStore: relayStore)
        let state = try #require(h.activities.only?.state)
        let activities = FakeLiveRankActivities()
        let pushed = activities.startedByPush(selfLogin: "me", state: state)
        let relay = FakeRelayClient()
        let keychain = InMemoryGitHubCredentialStore()  // locked: the token can't be read
        let unlocked = UnlockState()
        var dependencies = AppDependencies.testing(contributions: StubContributions(["me": 5, "alice": 9, "bob": 3]),
                                                   credentials: keychain, clock: h.clock)
        dependencies.competitorPersistence = h.dependencies.competitorPersistence
        dependencies.makeLiveRankActivities = { activities }
        dependencies.liveRankPersistence = h.persistence
        dependencies.relay = LiveRankRelayDependencies(client: relay, store: relayStore, environment: "sandbox")
        dependencies.isProtectedDataAvailable = { unlocked.value }
        let app = AppModel(dependencies)
        #expect(app.auth.isSignedIn == false)

        activities.issue(.activity(id: pushed.id, token: Data([0x42])))
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await app.liveRank.idle()

        #expect(relay.reportedActivities == ["\(pushed.id):42"])
        #expect(relay.unregisterCount == 0, "a locked phone isn't a disconnect")
        #expect(activities.ended.isEmpty)

        // Later the phone is unlocked and Committed opened, in the same process.
        unlocked.value = true
        keychain.save("gho_test")
        await app.sceneDidBecomeActive()
        await app.liveRank.idle()

        #expect(app.auth.isSignedIn, "the saved token is picked up, not Connect GitHub again")
        #expect(relay.unregisterCount == 0)
        #expect(activities.ended.isEmpty)
        #expect(activities.only?.id == pushed.id)
    }

    @Test func anUnregisterOwedFromALockedLaunchIsSentOnceThePhoneIsUnlocked() async throws {
        // Signed out earlier while the relay couldn't be reached, then launched in the background
        // while locked: whether GitHub is connected is unknown until the phone is unlocked.
        let relayStore = InMemoryLiveRankRelayStore()
        let h = await live(relayStore: relayStore)
        h.relay.failNext(.unreachable("offline"))
        h.app.disconnect()
        await h.app.liveRank.idle()
        #expect(h.relay.unregisterCount == 0)

        let relay = FakeRelayClient()
        let unlocked = UnlockState()
        var dependencies = AppDependencies.testing(contributions: StubContributions(), credentials: InMemoryGitHubCredentialStore())
        dependencies.liveRankPersistence = h.persistence
        dependencies.relay = LiveRankRelayDependencies(client: relay, store: relayStore, environment: "sandbox")
        dependencies.isProtectedDataAvailable = { unlocked.value }
        let app = AppModel(dependencies)
        app.liveRank.scheduleSync()
        await app.liveRank.idle()
        #expect(relay.unregisterCount == 0, "locked: not known to be signed out yet")

        unlocked.value = true
        await app.sceneDidBecomeActive()
        await app.liveRank.idle()

        #expect(relay.unregisterCount == 1)
    }

    final class UnlockState: @unchecked Sendable {
        var value = false
    }

    // MARK: - Re-registration

    @Test func hidingOrShowingSomeoneReRegistersTheVisibleBoard() async throws {
        let h = await live()
        h.relay.reset()

        h.app.setHidden(true, username: "alice")
        await h.app.liveRank.idle()
        #expect(h.relay.lastRegistration?.board.competitors == ["me", "bob"])

        await h.app.setHidden(false, username: "alice")?.value
        await h.app.liveRank.idle()
        #expect(h.relay.lastRegistration?.board.competitors == ["me", "alice", "bob"])
        #expect(h.relay.unregisterCount == 0)
    }

    @Test func changingTheLiveRankWindowReRegistersAndReportsTheNewActivity() async throws {
        let h = await live()
        h.relay.reset()

        await h.app.setLiveRankWindow(.weekly)
        await h.app.liveRank.idle()
        #expect(h.relay.lastRegistration?.board.window == "weekly")

        let weekly = try #require(h.activities.only?.id)
        h.activities.issue(.activity(id: weekly, token: Data([0x77])))
        await h.app.liveRank.idle()
        #expect(h.relay.reportedActivities == ["\(weekly):77"])
    }

    @Test func aPeopleSyncThatChangesTheRosterReRegisters() async throws {
        let h = await live()
        h.relay.reset()

        await h.app.refresh.refreshAll(reason: .timer)
        #expect(h.relay.calls.isEmpty, "nothing changed, nothing sent")

        FakeGitHub.reset(.init(login: "me", following: ["alice", "bob", "carol"]))
        await h.contributions.set("carol", 1)
        h.clock.advance(300)
        await h.app.refresh.refreshAll(reason: .manual)
        await h.app.liveRank.idle()

        #expect(h.relay.lastRegistration?.board.competitors == ["me", "alice", "bob", "carol"])
    }

    @Test func aTimeZoneChangeReRegisters() async throws {
        let h = await live()
        h.relay.reset()

        h.timeZone.zone = TimeZone(identifier: "Europe/Berlin")!
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await h.app.liveRank.idle()

        #expect(h.relay.lastRegistration?.board.timeZone == "Europe/Berlin")
    }

    // MARK: - Unregistration

    @Test func disconnectingDeletesTheRegistration() async throws {
        let h = await live()
        let install = try #require(h.relayStore.loadInstallation()?.id)

        h.app.disconnect()
        await h.app.liveRank.idle()

        #expect(h.relay.calls.last == .unregister(install: install))
        #expect(h.activities.activities.isEmpty)
    }

    @Test func turningLiveRankOffDeletesTheRegistrationAndOnRegistersAgain() async throws {
        let h = await live()
        let id = try #require(h.activities.only?.id)
        h.activities.issue(.activity(id: id, token: Data([0x01])))
        await h.app.liveRank.idle()

        await h.app.setLiveRankEnabled(false)
        await h.app.liveRank.idle()
        #expect(h.relay.unregisterCount == 1)
        h.relay.reset()

        await h.app.setLiveRankEnabled(true)
        await h.app.liveRank.idle()
        #expect(h.relay.registrations.count == 1)
        let restarted = try #require(h.activities.only?.id)
        h.activities.issue(.activity(id: restarted, token: Data([0x02])))
        await h.app.liveRank.idle()
        #expect(h.relay.reportedActivities == ["\(restarted):02"])
    }

    @Test func anUnregisterThatFailedIsRetriedOnTheNextLaunch() async throws {
        let relayStore = InMemoryLiveRankRelayStore()
        let h = await live(relayStore: relayStore)
        h.relay.failNext(.unreachable("offline"))
        await h.app.setLiveRankEnabled(false)
        await h.app.liveRank.idle()
        #expect(h.relay.unregisterCount == 0)

        let relay = FakeRelayClient()
        var dependencies = h.dependencies
        dependencies.relay = LiveRankRelayDependencies(client: relay, store: relayStore, environment: "sandbox")
        let relaunched = AppModel(dependencies)
        await relaunched.sceneDidBecomeActive()
        await relaunched.liveRank.idle()

        #expect(relay.unregisterCount == 1)
        #expect(relay.registrations.isEmpty)
    }

    // MARK: - Relay errors

    @Test func aFailedRegistrationIsRetriedOnTheNextSync() async throws {
        let relay = FakeRelayClient()
        relay.failNext(.unreachable("offline"))
        let h = connected(preferences: LiveRankPreferences(isEnabled: true, relayDisclosureAccepted: true), relay: relay)
        await h.app.sceneDidBecomeActive()
        #expect(relay.registrations.isEmpty)

        h.clock.advance(300)
        await h.app.refresh.refreshAll(reason: .timer)

        #expect(relay.registrations.count == 1)
    }

    @Test func tooManyRequestsWaitsForRetryAfter() async throws {
        let h = await live()
        h.relay.failNext(.rejected(status: 429, retryAfter: 120))
        h.app.setHidden(true, username: "alice")
        await h.app.liveRank.idle()
        h.relay.reset()

        h.clock.advance(60)
        h.app.setHidden(true, username: "bob")
        await h.app.liveRank.idle()
        #expect(h.relay.calls.isEmpty, "still inside Retry-After")

        h.clock.advance(61)
        await h.app.refresh.refreshAll(reason: .timer)
        #expect(h.relay.lastRegistration?.board.competitors == ["me"])
    }

    @Test func tooManyRequestsNeverHoldsUpTurningLiveRankOff() async throws {
        let h = await live()
        h.relay.failNext(.rejected(status: 429, retryAfter: 600))
        h.app.setHidden(true, username: "alice")
        await h.app.liveRank.idle()
        h.relay.reset()

        await h.app.setLiveRankEnabled(false)
        await h.app.liveRank.idle()

        #expect(h.relay.unregisterCount == 1, "the registration is deleted at once, inside Retry-After")
    }

    @Test func aRelayThatForgotThisIPhoneIsRegisteredAgain() async throws {
        let h = await live()
        let id = try #require(h.activities.only?.id)
        h.relay.failNext(.rejected(status: 404))
        h.activities.issue(.activity(id: id, token: Data([0x05])))
        await h.app.liveRank.idle()
        h.relay.reset()

        h.clock.advance(300)
        await h.app.refresh.refreshAll(reason: .timer)

        #expect(h.relay.registrations.count == 1)
        #expect(h.relay.reportedActivities == ["\(id):05"])
    }

    @Test func aRejectedSecretStartsOverWithANewInstallation() async throws {
        let relayStore = InMemoryLiveRankRelayStore()
        let h = await live(relayStore: relayStore)
        let old = try #require(relayStore.loadInstallation())
        h.relay.failNext(.rejected(status: 401))
        h.app.setHidden(true, username: "alice")
        await h.app.liveRank.idle()

        h.clock.advance(300)
        await h.app.refresh.refreshAll(reason: .timer)

        let new = try #require(relayStore.loadInstallation())
        #expect(new.id != old.id)
        let registration = try #require(h.relay.lastRegistration)
        #expect(h.relay.calls.last == .register(registration, install: new.id))
    }
}
}
