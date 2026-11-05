import Testing
import Foundation
@testable import CommitStandingsiOS

/// ActivityKit as Live rank uses it, in memory. Activity IDs count up from "1".
@MainActor
final class FakeLiveRankActivities: LiveRankActivities {
    var areActivitiesEnabled = true
    private(set) var activities: [LiveRankActivity] = []
    private(set) var started = 0
    private(set) var updated = 0
    private(set) var ended: [String] = []
    private var nextID = 1

    init(existing: [(selfLogin: String, state: LiveRankState)] = []) {
        for item in existing { _ = try? start(selfLogin: item.selfLogin, state: item.state, startedAt: .distantPast) }
        started = 0
    }

    func current() -> [LiveRankActivity] { activities }

    func start(selfLogin: String, state: LiveRankState, startedAt: Date) throws -> LiveRankActivity {
        let activity = LiveRankActivity(id: String(nextID), selfLogin: selfLogin, state: state, startedAt: startedAt)
        nextID += 1
        started += 1
        activities.append(activity)
        return activity
    }

    func update(id: String, to state: LiveRankState) async {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        updated += 1
        activities[index].state = state
    }

    func end(id: String) async {
        ended.append(id)
        activities.removeAll { $0.id == id }
    }

    /// iOS ends it on its own (the 8-hour limit, or the person swiped it away).
    func systemEnds(id: String) {
        activities.removeAll { $0.id == id }
    }

    private var tokenHandler: (@MainActor (LiveRankPushToken) -> Void)?
    var observingPushTokens: Bool { tokenHandler != nil }

    func observePushTokens(_ handler: @escaping @MainActor (LiveRankPushToken) -> Void) {
        tokenHandler = handler
    }

    /// ActivityKit hands out a push token.
    func issue(_ token: LiveRankPushToken) {
        tokenHandler?(token)
    }

    /// The relay started an activity with push-to-start (not counted as `started`).
    @discardableResult
    func startedByPush(selfLogin: String, state: LiveRankState) -> LiveRankActivity {
        let activity = LiveRankActivity(id: "push-\(nextID)", selfLogin: selfLogin, state: state)
        nextID += 1
        activities.append(activity)
        return activity
    }

    var only: LiveRankActivity? { activities.count == 1 ? activities[0] : nil }
}

/// Live rank on the device (phase 1): when its Live Activity starts, updates, and ends.
extension FakeGitHubSuites {
@Suite
@MainActor
struct LiveRankLifecycleTests {

    private struct Harness {
        let app: AppModel
        let activities: FakeLiveRankActivities
        let contributions: StubContributions
        let clock: TestClock
        let scheduled: ScheduleLog
    }

    final class ScheduleLog: @unchecked Sendable {
        var count = 0
    }

    /// Connected as "me" with alice and bob on the board, not yet refreshed.
    private func connected(
        preferences: LiveRankPreferences = LiveRankPreferences(),
        counts: [String: Int] = ["me": 5, "alice": 9, "bob": 3],
        activities: FakeLiveRankActivities = FakeLiveRankActivities()
    ) -> Harness {
        FakeGitHub.reset(.init(login: "me", following: ["alice", "bob"]))
        let clock = TestClock()
        let contributions = StubContributions(counts)
        let scheduled = ScheduleLog()
        var dependencies = AppDependencies.testing(
            contributions: contributions,
            credentials: InMemoryGitHubCredentialStore(token: "gho_test"),
            clock: clock
        )
        dependencies.makeLiveRankActivities = { activities }
        dependencies.liveRankPersistence = InMemoryLiveRankPersistence(preferences)
        dependencies.scheduleBackgroundRefresh = { scheduled.count += 1 }
        return Harness(app: AppModel(dependencies), activities: activities,
                       contributions: contributions, clock: clock, scheduled: scheduled)
    }

    @Test func startsOnceTheBoardLoadsWithYourRankAndNeighbors() async throws {
        let h = connected()

        await h.app.sceneDidBecomeActive()

        let activity = try #require(h.activities.only)
        #expect(activity.selfLogin == "me")
        #expect(activity.state.window == "daily")
        #expect(activity.state.rank == 2)
        #expect(activity.state.competitorCount == 3)
        #expect(activity.state.contributions == 5)
        #expect(activity.state.above == .init(login: "alice", contributions: 9))
        #expect(activity.state.below == .init(login: "bob", contributions: 3))
        #expect(activity.state.updatedAt == Int(h.clock.date.timeIntervalSince1970))
        #expect(h.app.liveRank.status == .live)
    }

    @Test func connectingStartsLiveRankWhenAllowed() async throws {
        FakeGitHub.reset(.init(polls: [.token("gho_new")], login: "me", following: ["alice"]))
        let activities = FakeLiveRankActivities()
        var dependencies = AppDependencies.testing(contributions: StubContributions(["me": 1, "alice": 2]))
        dependencies.makeLiveRankActivities = { activities }
        let app = AppModel(dependencies)
        await app.sceneDidBecomeActive()
        #expect(activities.activities.isEmpty, "nothing before Connect GitHub")

        await app.auth.signIn()

        #expect(activities.only?.state.rank == 2)
    }

    @Test func staysOffWhenTurnedOff() async {
        let h = connected(preferences: LiveRankPreferences(isEnabled: false))

        await h.app.sceneDidBecomeActive()

        #expect(h.activities.activities.isEmpty)
        #expect(h.app.liveRank.status == .off)
    }

    @Test func updatesOnlyWhenTheStateChanged() async throws {
        let h = connected()
        await h.app.sceneDidBecomeActive()
        let id = try #require(h.activities.only?.id)

        await h.app.refresh.refreshAll(reason: .manual)
        #expect(h.activities.updated == 0, "same numbers at the same time: no update")

        await h.contributions.set("me", 10)
        h.clock.advance(300)
        await h.app.refresh.refreshAll(reason: .timer)

        #expect(h.activities.updated == 1)
        #expect(h.activities.only?.id == id, "the same activity, updated in place")
        #expect(h.activities.only?.state.rank == 1)
        #expect(h.activities.only?.state.below == .init(login: "alice", contributions: 9))
    }

    @Test func sameNumbersLaterAreNoUpdateUntilTheStaleDateIsNear() async throws {
        let h = connected()
        await h.app.sceneDidBecomeActive()  // its stale date is 20 minutes away

        h.clock.advance(300)
        await h.app.refresh.refreshAll(reason: .timer)
        #expect(h.activities.updated == 0, "same numbers, later time: nothing new to show")

        h.clock.advance(300)  // the stale date is now 10 minutes away
        await h.app.refresh.refreshAll(reason: .timer)
        #expect(h.activities.updated == 1, "a heartbeat moves the stale date before it passes")
        #expect(h.activities.only?.state.updatedAt == Int(h.clock.date.timeIntervalSince1970))

        h.clock.advance(300)
        await h.app.refresh.refreshAll(reason: .timer)
        #expect(h.activities.updated == 1, "the new stale date is far away again")
    }

    @Test func backgroundRefreshUpdatesButNeverStartsUntilTheAppIsOpen() async throws {
        let h = connected()
        await h.app.sceneDidBecomeActive()
        h.app.sceneDidEnterBackground()
        #expect(h.scheduled.count == 1, "leaving the foreground schedules a background refresh")

        await h.contributions.set("bob", 20)
        h.clock.advance(900)
        await h.app.backgroundRefresh()
        #expect(h.activities.only?.state.rank == 3)
        #expect(h.scheduled.count == 2, "each background refresh schedules the next")

        h.activities.systemEnds(id: try #require(h.activities.only?.id))
        h.clock.advance(900)
        await h.app.backgroundRefresh()
        #expect(h.activities.activities.isEmpty, "iOS can't start one from the background")

        h.clock.advance(60)
        await h.app.sceneDidBecomeActive()
        #expect(h.activities.only != nil, "it restarts once the app is open")
    }

    @Test func disconnectingEndsLiveRank() async throws {
        let h = connected()
        await h.app.sceneDidBecomeActive()
        let id = try #require(h.activities.only?.id)

        h.app.auth.signOut()
        await h.app.liveRank.idle()

        #expect(h.activities.activities.isEmpty)
        #expect(h.activities.ended == [id])
        await h.app.sceneDidBecomeActive()
        #expect(h.activities.activities.isEmpty, "signed out: nothing restarts")
    }

    @Test func turningLiveRankOffEndsItAndOnStartsItAgain() async throws {
        let h = connected()
        await h.app.sceneDidBecomeActive()

        await h.app.setLiveRankEnabled(false)
        #expect(h.activities.activities.isEmpty)
        #expect(h.app.liveRank.status == .off)
        #expect(h.app.liveRank.isEnabled == false)

        await h.app.setLiveRankEnabled(true)
        #expect(h.activities.only?.state.rank == 2)
    }

    @Test func changingTheWindowEndsTheActivityAndStartsOneForTheNewWindow() async throws {
        let h = connected()
        await h.app.sceneDidBecomeActive()
        let daily = try #require(h.activities.only?.id)

        await h.app.setLiveRankWindow(.weekly)

        #expect(h.activities.ended == [daily])
        let weekly = try #require(h.activities.only)
        #expect(weekly.id != daily)
        #expect(weekly.state.window == "weekly")
        #expect(weekly.state.contributions == 5, "7 days was fetched for Live rank while the board shows Today")
        #expect(h.app.store.selectedWindow == .daily, "the board keeps its own Window")
        #expect(h.app.liveRank.window == .weekly)
    }

    @Test func strayActivitiesAreEndedOnLaunch() async throws {
        let old = LiveRankState(window: "daily", rank: 1, competitorCount: 2, contributions: 1,
                                above: nil, below: nil, movementToday: 0, updatedAt: 0)
        var otherWindow = old
        otherWindow.window = "monthly"
        let activities = FakeLiveRankActivities(existing: [
            ("me", old), ("me", old), ("someone-else", old), ("me", otherWindow),
        ])
        let h = connected(activities: activities)

        await h.app.sceneDidBecomeActive()

        let kept = try #require(h.activities.only)
        #expect(kept.id == "1", "the oldest matching activity stays and is updated")
        #expect(kept.state.rank == 2)
        #expect(Set(h.activities.ended) == ["2", "3", "4"])
        #expect(h.activities.started == 0)
    }

    @Test func hidingSomeoneUpdatesLiveRankRightAway() async throws {
        let h = connected()
        await h.app.sceneDidBecomeActive()

        h.app.setHidden(true, username: "alice")
        await h.app.liveRank.idle()

        let state = try #require(h.activities.only?.state)
        #expect(state.rank == 1)
        #expect(state.competitorCount == 2)
        #expect(state.above == nil)
    }

    @Test func liveActivitiesOffInIOSSettingsIsReported() async {
        let activities = FakeLiveRankActivities()
        activities.areActivitiesEnabled = false
        let h = connected(activities: activities)

        await h.app.sceneDidBecomeActive()

        #expect(h.activities.activities.isEmpty)
        #expect(h.app.liveRank.status == .disabledInSystem)

        activities.areActivitiesEnabled = true
        h.clock.advance(30)
        await h.app.sceneDidBecomeActive()
        #expect(h.activities.only != nil, "turned back on in Settings: starts on return")
        #expect(h.app.liveRank.status == .live)
    }

    @Test func settingsSurviveRelaunch() async {
        let persistence = InMemoryLiveRankPersistence()
        FakeGitHub.reset(.init(login: "me"))
        var dependencies = AppDependencies.testing(contributions: StubContributions())
        dependencies.liveRankPersistence = persistence
        let first = AppModel(dependencies)
        await first.setLiveRankWindow(.monthly)
        await first.setLiveRankEnabled(false)

        let relaunched = AppModel(dependencies)

        #expect(relaunched.liveRank.window == .monthly)
        #expect(relaunched.liveRank.isEnabled == false)
        #expect(persistence.loadPreferences() == LiveRankPreferences(isEnabled: false, window: .monthly))
    }
}
}
