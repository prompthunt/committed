import Testing
import Foundation
@testable import CommitStandingsiOS

/// When the iPhone app refreshes: on becoming active only when stale, every interval while
/// active, never on the timer in the background, and on a Window switch only when stale.
extension FakeGitHubSuites {
@Suite
@MainActor
struct AppLifecycleTests {

    /// A connected app whose board was loaded at `clock.date`.
    private func connectedApp(
        clock: TestClock,
        contributions: StubContributions,
        timer: ManualTimer = ManualTimer()
    ) async -> AppModel {
        FakeGitHub.reset(.init(login: "me", following: ["alice"]))
        var dependencies = AppDependencies.testing(
            contributions: contributions,
            credentials: InMemoryGitHubCredentialStore(token: "gho_test"),
            clock: clock
        )
        dependencies.timerSleep = timer.sleep
        let app = AppModel(dependencies)
        await app.refresh.refreshAll(reason: .manual)
        return app
    }

    @Test func becomingActiveRefreshesOnlyWhenTheBoardIsOlderThanTwoMinutes() async {
        let clock = TestClock()
        let contributions = StubContributions(["me": 1, "alice": 2])
        let app = await connectedApp(clock: clock, contributions: contributions)
        let afterLoad = await contributions.callCount()
        #expect(afterLoad == 2)

        clock.advance(90)
        await app.sceneDidBecomeActive()
        #expect(await contributions.callCount() == afterLoad, "fresh data: no refresh, no flashing")

        clock.advance(60)
        await app.sceneDidBecomeActive()
        #expect(await contributions.callCount() == afterLoad + 2, "stale data: one refresh of everyone")
    }

    @Test func becomingActiveWhileSignedOutFetchesNothing() async {
        FakeGitHub.reset(.init())
        let contributions = StubContributions()
        let app = AppModel(.testing(contributions: contributions))

        await app.sceneDidBecomeActive()

        #expect(await contributions.callCount() == 0)
    }

    @Test func theTimerRefreshesWhileActiveAndPausesInTheBackground() async throws {
        let clock = TestClock()
        let contributions = StubContributions(["me": 1, "alice": 2])
        let timer = ManualTimer()
        let app = await connectedApp(clock: clock, contributions: contributions, timer: timer)
        let loaded = await contributions.callCount()

        await timer.tick()
        #expect(await contributions.callCount() == loaded + 2, "a timer tick refreshes everyone")

        app.sceneDidEnterBackground()
        #expect(!timer.isWaiting, "no timer refreshes in the background")

        await app.sceneDidBecomeActive()
        await timer.tick()
        #expect(await contributions.callCount() == loaded + 4, "the timer runs again once active")
        app.sceneDidEnterBackground()
    }

    @Test func switchingToACachedWindowShowsItsNumbersWithoutFetching() async {
        let clock = TestClock()
        let contributions = StubContributions(["me": 1, "alice": 2])
        let app = await connectedApp(clock: clock, contributions: contributions)

        app.store.selectedWindow = .weekly
        await app.windowDidChange()
        let afterWeekly = await contributions.callCount()
        #expect(afterWeekly == 4, "7 days had never loaded")

        clock.advance(30)
        app.store.selectedWindow = .daily
        await app.windowDidChange()
        #expect(await contributions.callCount() == afterWeekly, "Today is cached and fresh")
        #expect(Board(store: app.store, refresh: app.refresh).rows.map { $0.standing?.contributions } == [2, 1])

        clock.advance(200)
        app.store.selectedWindow = .weekly
        await app.windowDidChange()
        #expect(await contributions.callCount() == afterWeekly + 2, "7 days went stale")
    }
}
}
