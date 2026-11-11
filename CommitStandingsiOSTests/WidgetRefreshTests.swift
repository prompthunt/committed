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

    /// What the app saves: me #2 (moved up 1 today, 4-day streak), ada #1 (9 days), bo #3 (down 1,
    /// no streak).
    private func appSnapshot(window: ContributionWindow = .daily, sample: Bool? = nil, people: [String]? = ["me", "ada", "bo"],
                             at savedAt: Date? = nil) -> WidgetSnapshot {
        let board: [WidgetSnapshot.Row] = [
            .init(rank: 1, login: "ada", contributions: 5, movement: 0, isSelf: false, streak: 9),
            .init(rank: 2, login: "me", contributions: 3, movement: 1, isSelf: true, streak: 4),
            .init(rank: 3, login: "bo", contributions: 1, movement: -1, isSelf: false, streak: 0),
        ]
        return WidgetSnapshot(
            selfLogin: "me",
            state: LiveRankState(
                window: window.rawValue, rank: 2, competitorCount: 3, contributions: 3,
                above: .init(login: "ada", contributions: 5, movementToday: 0, streak: 9),
                below: .init(login: "bo", contributions: 1, movementToday: -1, streak: 0),
                movementToday: 1, streak: 4, updatedAt: Int((savedAt ?? saved).timeIntervalSince1970)
            ),
            top: board, isSampleBoard: sample, people: people, board: board
        )
    }

    private func refresh(_ snapshot: WidgetSnapshot?, counts: [String: Int],
                         histories: [String: ContributionHistory] = [:], at now: Date) async
        -> (shown: WidgetSnapshot?, savedBack: [WidgetSnapshot], fetcher: FakeContributions) {
        let fetcher = FakeContributions(counts, histories: histories)
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

    // MARK: This month

    /// Within the month, This month works like Today: anyone GitHub didn't answer for keeps their
    /// count, and today's movement carries on.
    @Test func thisMonthKeepsLastCountsAndCarriesTodaysMovementOn() {
        let now = saved.addingTimeInterval(15 * 60)
        let next = appSnapshot(window: .month).refreshed(counts: ["me": 7], now: now, calendar: utc)

        #expect(next.state.window == "month")
        #expect(next.board?.map(\.login) == ["me", "ada", "bo"])
        #expect(next.board?.map(\.contributions) == [7, 5, 1])
        // You started the day #3 and are #1: up 2. Ada started #1 and is #2.
        #expect(next.board?.map(\.movement) == [2, -1, -1])
        #expect(next.state.movementToday == 2)
        #expect(next.state.below?.movementToday == -1)
    }

    /// After midnight mid-month, the counts still belong to this month: they're kept, and the new
    /// day's movement starts at 0.
    @Test func thisMonthKeepsLastCountsAcrossMidnightMidMonth() {
        let tomorrow = saved.addingTimeInterval(24 * 3600)
        let next = appSnapshot(window: .month).refreshed(counts: ["me": 9], now: tomorrow, calendar: utc)

        #expect(next.board?.map(\.contributions) == [9, 5, 1])
        #expect(next.board?.map(\.movement) == [0, 0, 0])
    }

    /// On the 1st, last month's totals are not this month's: anyone GitHub didn't answer for shows
    /// no data rather than carrying May into June, and movement starts again.
    @Test func aNewMonthDropsLastMonthsCounts() throws {
        let lastEvening = try #require(utc.date(from: DateComponents(year: 2033, month: 5, day: 31, hour: 23, minute: 50)))
        let firstOfJune = lastEvening.addingTimeInterval(15 * 60)
        let next = appSnapshot(window: .month, at: lastEvening)
            .refreshed(counts: ["me": 2, "bo": 4], now: firstOfJune, calendar: utc)

        #expect(next.board?.map(\.login) == ["bo", "me", "ada"])
        #expect(next.board?.map(\.contributions) == [4, 2, nil])
        #expect(next.board?.map(\.movement) == [0, 0, 0])
        #expect(next.state.contributions == 2)
        #expect(next.state.movementToday == 0)
    }

    /// Through the real client, This month is the 1st of the month to today from each calendar:
    /// 2033-05-01...05-18 here, where 7 days would rank bo first.
    @Test func thisMonthComesFromTheirCalendars() async throws {
        let now = saved.addingTimeInterval(15 * 60) // 2033-05-18 03:48 UTC
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CalendarPages.self]
        let client = ContributionsClient(session: URLSession(configuration: config), timeZone: { TimeZone(identifier: "UTC")! })
        let box = SnapshotBox(appSnapshot(window: .month))
        let refresh = WidgetRefresh(fetcher: client, load: { box.value }, save: { box.write($0) })

        let shown = try #require(await refresh.current(now: now, calendar: utc))

        #expect(shown.board?.map(\.login) == ["me", "bo", "ada"])
        #expect(shown.board?.map(\.contributions) == [58, 9, 5])
    }

    // MARK: Streaks

    /// Each person's streak comes from the calendar their page just brought back, as of now, the
    /// same rule as the Board's rows.
    @Test func streaksComeFromTheCalendarsItFetches() async throws {
        let now = saved.addingTimeInterval(15 * 60) // 2033-05-18 03:48 UTC
        let utc = TimeZone(identifier: "UTC")!
        let histories = [
            // Nothing yet today: alive on yesterday's run.
            "me": ContributionHistory(days: ["2033-05-15": 0, "2033-05-16": 1, "2033-05-17": 2, "2033-05-18": 0], timeZone: utc),
            "ada": ContributionHistory(days: ["2033-05-17": 0, "2033-05-18": 5], timeZone: utc),
            "bo": ContributionHistory(days: ["2033-05-16": 3, "2033-05-17": 0, "2033-05-18": 0], timeZone: utc),
        ]
        let (shown, _, _) = await refresh(appSnapshot(), counts: ["me": 7, "ada": 5, "bo": 1], histories: histories, at: now)

        let next = try #require(shown)
        #expect(next.board?.map(\.login) == ["me", "ada", "bo"])
        #expect(next.board?.map(\.streak) == [2, 1, 0])
        #expect(next.top.map(\.streak) == [2, 1, 0])
        #expect(next.state.streak == 2)
        #expect(next.state.below?.streak == 1)
    }

    /// Like their count, someone GitHub didn't answer for keeps the streak they had that day.
    @Test func someoneGitHubDidNotAnswerForKeepsTheirStreakThatDay() {
        let now = saved.addingTimeInterval(15 * 60)
        let next = appSnapshot().refreshed(counts: ["me": 4], streaks: ["me": 5], now: now, calendar: utc)

        #expect(next.board?.map(\.login) == ["ada", "me", "bo"])
        #expect(next.board?.map(\.streak) == [9, 5, 0])
        #expect(next.state.streak == 5)
        #expect(next.state.above?.streak == 9)
        #expect(next.state.below?.streak == 0)
    }

    /// After midnight a saved streak may have grown or broken, and there's no calendar to tell: it
    /// isn't shown (never a wrong one), even where the Window keeps the last count.
    @Test func aNewDayDropsTheStreaksOfThoseWhoDidNotAnswer() {
        let tomorrow = saved.addingTimeInterval(24 * 3600)
        let next = appSnapshot(window: .weekly).refreshed(counts: ["me": 9], streaks: ["me": 5], now: tomorrow, calendar: utc)

        #expect(next.board?.map(\.contributions) == [9, 5, 1])
        #expect(next.board?.map(\.streak) == [5, nil, nil])
        #expect(next.state.below?.streak == nil)
    }

    /// Your streak follows your count: with no count to show, no streak.
    @Test func noStreakForYouWithoutYourCount() {
        let tomorrow = saved.addingTimeInterval(24 * 3600)
        let next = appSnapshot().refreshed(counts: ["ada": 2], streaks: ["ada": 10], now: tomorrow, calendar: utc)

        #expect(next.state.contributions == nil)
        #expect(next.state.streak == nil)
        #expect(next.selfRow == nil)
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

    /// Through the real client: each person's one page carries their calendar, and the widget's
    /// Window total is worked out from those days by `ContributionHistory`, as on the Board.
    @Test func eachPersonsWindowComesFromTheirCalendar() async throws {
        let now = saved.addingTimeInterval(15 * 60) // 2033-05-18 03:48 UTC
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CalendarPages.self]
        let client = ContributionsClient(session: URLSession(configuration: config), timeZone: { TimeZone(identifier: "UTC")! })
        let box = SnapshotBox(appSnapshot(window: .weekly))
        let refresh = WidgetRefresh(fetcher: client, load: { box.value }, save: { box.write($0) })

        let shown = try #require(await refresh.current(now: now, calendar: utc))

        #expect(shown.board?.map(\.login) == ["bo", "me", "ada"])
        #expect(shown.board?.map(\.contributions) == [9, 8, 5])
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

/// github.com's contribution pages for the people in `appSnapshot`, one calendar each.
private final class CalendarPages: URLProtocol {
    static let pages: [String: String] = [
        // 7 days as of 2033-05-18 is 05-12...05-18.
        "/users/me/contributions": #"<td data-date="2033-05-11" data-count="50"></td><td data-date="2033-05-17" data-count="4"></td><td data-date="2033-05-18" data-count="4"></td>"#,
        "/users/ada/contributions": #"<td data-date="2033-05-12" data-count="3"></td><td data-date="2033-05-18" data-count="2"></td>"#,
        "/users/bo/contributions": #"<td data-date="2033-05-15" data-count="9"></td><td data-date="2033-05-19" data-count="100"></td>"#,
    ]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.url.flatMap { Self.pages[$0.path] }
        let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
