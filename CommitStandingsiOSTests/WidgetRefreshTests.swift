import Foundation
import Testing
@testable import CommitStandingsiOS

/// The widgets' own 15-minute refresh (`WidgetRefresh`): refetch everyone the app saved, re-rank
/// as the app does, carry today's movement on, and save the result back to the App Group.
struct WidgetRefreshTests {
    /// 2033-05-18 03:33:20 UTC: a fixed clock, mid-afternoon nowhere in particular.
    let saved = Date(timeIntervalSince1970: 2_000_000_000)
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// What the app saves: me #2 (moved up 1 today), ada #1, bo #3 (down 1).
    private func appSnapshot(window: ContributionWindow = .daily, sample: Bool? = nil, people: [String]? = ["me", "ada", "bo"]) -> WidgetSnapshot {
        let board: [WidgetSnapshot.Row] = [
            .init(rank: 1, login: "ada", contributions: 5, movement: 0, isSelf: false),
            .init(rank: 2, login: "me", contributions: 3, movement: 1, isSelf: true),
            .init(rank: 3, login: "bo", contributions: 1, movement: -1, isSelf: false),
        ]
        return WidgetSnapshot(
            selfLogin: "me",
            state: LiveRankState(
                window: window.rawValue, rank: 2, competitorCount: 3, contributions: 3,
                above: .init(login: "ada", contributions: 5, movementToday: 0),
                below: .init(login: "bo", contributions: 1, movementToday: -1),
                movementToday: 1, updatedAt: Int(saved.timeIntervalSince1970)
            ),
            top: board, isSampleBoard: sample, people: people, board: board
        )
    }

    private func refresh(_ snapshot: WidgetSnapshot?, counts: [String: Int], at now: Date) async
        -> (shown: WidgetSnapshot?, savedBack: [WidgetSnapshot], fetcher: FakeContributions) {
        let fetcher = FakeContributions(counts)
        let store = SnapshotBox(snapshot)
        let refresh = WidgetRefresh(fetcher: fetcher, load: { store.value }, save: { store.write($0) })
        let shown = await refresh.current(now: now, calendar: utc)
        return (shown, store.writes, fetcher)
    }

    // MARK: Re-ranking

    @Test func reRanksWithNewCountsAndCarriesTodaysMovementOn() {
        let now = saved.addingTimeInterval(15 * 60)
        // I pass ada: 3 → 7.
        let next = appSnapshot().refreshed(counts: ["me": 7, "ada": 5, "bo": 1], now: now, calendar: utc)

        #expect(next.board?.map(\.login) == ["me", "ada", "bo"])
        #expect(next.top.map(\.login) == ["me", "ada", "bo"])
        // Baseline was #3 (moved up 1 to #2); now #1, so up 2. Ada was #1 at 0, now #2: down 1.
        #expect(next.board?.map(\.movement) == [2, -1, -1])
        #expect(next.state.rank == 1)
        #expect(next.state.contributions == 7)
        #expect(next.state.movementToday == 2)
        #expect(next.state.above == nil)
        #expect(next.state.below?.login == "ada")
        #expect(next.state.updatedDate == now)
        #expect(next.people == ["me", "ada", "bo"])
    }

    @Test func someoneGitHubDidNotAnswerForKeepsTheirLastCount() {
        let now = saved.addingTimeInterval(15 * 60)
        let next = appSnapshot().refreshed(counts: ["me": 4], now: now, calendar: utc)

        #expect(next.board?.map(\.contributions) == [5, 4, 1])
        #expect(next.state.passLine == "1 to pass ada")
    }

    @Test func aNewDayResetsTodaysMovementAndDropsYesterdaysCounts() {
        let tomorrow = saved.addingTimeInterval(24 * 3600)
        let next = appSnapshot().refreshed(counts: ["me": 2, "bo": 4], now: tomorrow, calendar: utc)

        #expect(next.board?.map(\.login) == ["bo", "me", "ada"])
        // Ada didn't answer: yesterday's 5 isn't today's, so no data, never a stale count.
        #expect(next.board?.map(\.contributions) == [4, 2, nil])
        #expect(next.board?.map(\.movement) == [0, 0, 0])
        #expect(next.state.movementToday == 0)
    }

    @Test func sevenDaysKeepsLastCountsAcrossMidnightWithoutMovement() {
        let tomorrow = saved.addingTimeInterval(24 * 3600)
        let next = appSnapshot(window: .weekly).refreshed(counts: ["me": 9], now: tomorrow, calendar: utc)

        #expect(next.board?.map(\.login) == ["me", "ada", "bo"])
        #expect(next.board?.map(\.contributions) == [9, 5, 1])
        #expect(next.board?.map(\.movement) == [0, 0, 0])
    }

    @Test func tiesGoToYouAsOnTheBoard() {
        let now = saved.addingTimeInterval(15 * 60)
        let next = appSnapshot().refreshed(counts: ["me": 5, "ada": 5, "bo": 1], now: now, calendar: utc)

        #expect(next.board?.map(\.login) == ["me", "ada", "bo"])
        #expect(next.state.rank == 1)
    }

    // MARK: When it fetches

    @Test func fetchesEveryoneAndSavesTheResultBack() async {
        let now = saved.addingTimeInterval(15 * 60)
        let (shown, writes, fetcher) = await refresh(appSnapshot(), counts: ["me": 7, "ada": 5, "bo": 2], at: now)

        #expect(await fetcher.total() == 3)
        #expect(shown?.state.rank == 1)
        #expect(shown?.state.updatedDate == now)
        #expect(writes.count == 1)
        #expect(writes.first == shown)
    }

    @Test func freshNumbersFromTheAppAreShownWithoutFetching() async {
        let now = saved.addingTimeInterval(4 * 60)
        let (shown, writes, fetcher) = await refresh(appSnapshot(), counts: ["me": 7], at: now)

        #expect(await fetcher.total() == 0)
        #expect(shown == appSnapshot())
        #expect(writes.isEmpty)
    }

    @Test func theSampleBoardIsNeverFetched() async {
        let now = saved.addingTimeInterval(60 * 60)
        let (shown, writes, fetcher) = await refresh(appSnapshot(sample: true), counts: ["me": 7], at: now)

        #expect(await fetcher.total() == 0)
        #expect(shown?.state.updatedDate == saved)
        #expect(writes.isEmpty)
    }

    @Test func aSnapshotWithoutPeopleShowsAsSaved() async {
        let now = saved.addingTimeInterval(60 * 60)
        let (shown, _, fetcher) = await refresh(appSnapshot(people: nil), counts: ["me": 7], at: now)

        #expect(await fetcher.total() == 0)
        #expect(shown?.state.rank == 2)
    }

    @Test func whenNobodyAnswersTheSavedNumbersStayAndKeepAging() async {
        let now = saved.addingTimeInterval(60 * 60)
        let (shown, writes, fetcher) = await refresh(appSnapshot(), counts: [:], at: now)

        #expect(await fetcher.total() == 3)
        #expect(shown?.state.updatedDate == saved)
        #expect(writes.isEmpty)
    }

    @Test func notConnectedShowsNothing() async {
        let (shown, _, fetcher) = await refresh(nil, counts: ["me": 7], at: saved)

        #expect(shown == nil)
        #expect(await fetcher.total() == 0)
    }

    // MARK: Staleness

    @Test func widgetsLookStaleAnHourAfterTheirData() {
        let snapshot = appSnapshot()
        #expect(snapshot.staleDate == saved.addingTimeInterval(3600))
    }
}

/// The App Group file, in memory.
private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: WidgetSnapshot?
    private(set) var writes: [WidgetSnapshot] = []

    init(_ value: WidgetSnapshot?) { current = value }

    var value: WidgetSnapshot? { lock.withLock { current } }

    func write(_ snapshot: WidgetSnapshot) {
        lock.withLock {
            current = snapshot
            writes.append(snapshot)
        }
    }
}
