import Testing
import Foundation
@testable import CommitStandings

/// Final standings: a finished month's ranks and medals among the people on your board, worked out
/// from each person's saved calendar with the board's own ranking (`Ranking.order`). Tested through
/// the store, the seam the Board, the share image (#100) and the person view (#101) read.
@MainActor
struct FinalStandingsTests {
    static let october = CalendarMonth(year: 2026, month: 10)

    /// A calendar from `first` through `last` (inclusive, `"YYYY-MM-DD"`), zero every day except
    /// `counts`.
    static func history(from first: String = "2026-09-14", through last: String = "2026-11-01",
                        _ counts: [String: Int] = [:]) -> ContributionHistory {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let format = Date.ISO8601FormatStyle().year().month().day()
        var day = try! format.parse(first)
        let end = try! format.parse(last)
        var days: [String: Int] = [:]
        while day <= end {
            days[ContributionHistory.key(for: day, in: calendar)] = 0
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        days.merge(counts) { _, new in new }
        return ContributionHistory(days: days, timeZone: .gmt)
    }

    /// "me" and `rivals`, each with an October total (spread over two days), in board order.
    static func store(_ totals: [String: Int], rivals: [String]) -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: rivals)
        var histories: [String: ContributionHistory] = [:]
        for (login, total) in totals {
            histories[login] = history(["2026-10-01": total / 2, "2026-10-31": total - total / 2,
                                        "2026-09-30": 99, "2026-11-01": 99])
        }
        store.updateHistories(histories)
        return store
    }

    static func summary(_ finals: FinalStandings?) -> [String] {
        (finals?.entries ?? []).map { entry in
            "#\(entry.rank) \(entry.competitor.username) \(entry.contributions.map(String.init) ?? "—")"
                + (entry.medal.map { " \($0)" } ?? "")
        }
    }

    @Test func lastMonthsTotalsRankEveryoneWithMedalsOnTheTopThree() {
        let store = Self.store(["me": 30, "ana": 51, "bo": 10, "cy": 20, "di": 0], rivals: ["ana", "bo", "cy", "di"])
        let finals = store.finalStandings(for: Self.october)
        #expect(finals?.month == Self.october)
        #expect(Self.summary(finals) == [
            "#1 ana 51 gold", "#2 me 30 silver", "#3 cy 20 bronze", "#4 bo 10", "#5 di 0",
        ])
    }

    @Test func aZeroTotalNeverEarnsAMedal() {
        let store = Self.store(["me": 4, "ana": 0, "bo": 0], rivals: ["ana", "bo"])
        #expect(Self.summary(store.finalStandings(for: Self.october)) == ["#1 me 4 gold", "#2 ana 0", "#3 bo 0"])
    }

    @Test func youWinTies() {
        let store = Self.store(["me": 20, "ana": 20, "bo": 20], rivals: ["ana", "bo"])
        #expect(Self.summary(store.finalStandings(for: Self.october)) == [
            "#1 me 20 gold", "#2 ana 20 silver", "#3 bo 20 bronze",
        ])
    }

    @Test func hidingSomeoneChangesFinishes() {
        let store = Self.store(["me": 30, "ana": 51, "bo": 10, "cy": 20], rivals: ["ana", "bo", "cy"])
        store.setHidden(true, username: "ana")
        #expect(Self.summary(store.finalStandings(for: Self.october)) == ["#1 me 30 gold", "#2 cy 20 silver", "#3 bo 10 bronze"])
        store.setHidden(false, username: "ana")
        #expect(store.finalStandings(for: Self.october)?.entry(for: "ana")?.medal == .gold)
    }

    /// Someone whose calendar hasn't loaded ranks last without a medal, never as a zero.
    @Test func someoneWithoutACalendarRanksLastWithNoTotal() {
        let store = Self.store(["me": 3, "ana": 8], rivals: ["ana", "new-person"])
        #expect(Self.summary(store.finalStandings(for: Self.october)) == ["#1 ana 8 gold", "#2 me 3 silver", "#3 new-person —"])
    }

    /// Months are offered from your own calendar's first full month through last month (in the
    /// device's calendar); your calendar here starts mid-September and was read on November 1.
    @Test func onlyFinishedMonthsYourCalendarCoversInFullAreOffered() {
        let store = Self.store(["me": 3, "ana": 8], rivals: ["ana"])
        #expect(store.finalStandings(for: CalendarMonth(year: 2026, month: 9)) == nil)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let november1 = Date(timeIntervalSince1970: 1_793_512_800) // 2026-11-01T06:00Z
        #expect(store.finishedMonths(asOf: november1, calendar: utc) == [Self.october])
        store.updateHistories(["me": Self.history(from: "2026-08-01", through: "2026-11-01")])
        #expect(store.finishedMonths(asOf: november1, calendar: utc).map(\.key) == ["2026-10", "2026-09", "2026-08"])
        // Nothing to offer without your own calendar.
        let empty = StandingsStore(persistence: InMemoryCompetitorPersistence())
        empty.replaceRoster(owner: "me", members: ["ana"])
        empty.updateHistories(["ana": Self.history()])
        #expect(empty.finalStandings(for: Self.october) == nil)
    }

    @Test func theResultReadsAsTheNotificationDoes() {
        let store = Self.store(["me": 30, "ana": 51, "bo": 10], rivals: ["ana", "bo"])
        let result = store.finalStandings(for: Self.october)?.result
        #expect(result?.title == "October final")
        #expect(result?.body == "You finished #2 of 3")
    }
}

/// The Board on the 1st and the month-final Leaderboard Notification, through the refresh
/// coordinator with a stubbed GitHub and an injected clock and calendar.
@MainActor
struct MonthFinalTests {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    static let november1 = Date(timeIntervalSince1970: 1_793_512_800) // 2026-11-01T06:00Z
    static let november2 = Date(timeIntervalSince1970: 1_793_599_200) // 2026-11-02T06:00Z
    static let december1 = Date(timeIntervalSince1970: 1_796_104_800) // 2026-12-01T06:00Z

    @MainActor final class Spy: RankChangeNotifying {
        var monthFinals: [(id: String, title: String, body: String)] = []
        func post(_ events: [RankChangeEvent]) {}
        func postMonthFinal(id: String, title: String, body: String) -> Bool {
            monthFinals.append((id, title, body))
            return true
        }
    }

    struct Board {
        let store: StandingsStore
        let refresh: RefreshCoordinator
        let client: StubFetcher
        let clock: MutableClock
        let spy: Spy
    }

    /// Saved months as if `owners` last heard about September: the next 1st announces October.
    static func announcedSeptember(_ owners: [String] = ["me"]) -> InMemoryAnnouncedMonthPersistence {
        let announced = InMemoryAnnouncedMonthPersistence()
        announced.save(Dictionary(uniqueKeysWithValues: owners.map { ($0, "2026-09") }))
        return announced
    }

    /// "me", "ana" and "bo" with October totals 30, 51 and 10, calendars through `date`'s day in
    /// `calendar` (or through `lastDay`).
    static func board(
        at date: Date = november1,
        announced: any AnnouncedMonthPersistence = announcedSeptember(),
        store: StandingsStore? = nil,
        notifier: Spy = Spy(),
        calendar: Calendar = utc,
        lastDay: String? = nil
    ) async -> Board {
        let store = store ?? {
            let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
            store.replaceRoster(owner: "me", members: ["ana", "bo"])
            return store
        }()
        let client = StubFetcher()
        await setCalendars(client, lastDay: lastDay ?? ContributionHistory.key(for: date, in: calendar))
        let clock = MutableClock(date)
        let refresh = RefreshCoordinator(
            store: store, client: client, interval: 9_999, now: { clock.date }, notifier: notifier,
            calendar: calendar, announcedMonths: announced
        )
        return Board(store: store, refresh: refresh, client: client, clock: clock, spy: notifier)
    }

    static func setCalendars(_ client: StubFetcher, through date: Date) async {
        await setCalendars(client, lastDay: ContributionHistory.key(for: date, in: utc))
    }

    static func setCalendars(_ client: StubFetcher, lastDay: String) async {
        for (login, total) in ["me": 30, "ana": 51, "bo": 10] {
            let history = FinalStandingsTests.history(through: lastDay, ["2026-10-15": total])
            await client.setResponse(.success(StandingCounts(contributions: 0, history: history)), for: login)
        }
    }

    @Test func theBoardOffersLastMonthsFinalStandingsAllDayOnThe1st() async {
        let board = await Self.board()
        #expect(board.refresh.offeredFinalStandings == nil) // nothing saved yet
        await board.refresh.refreshAll(reason: .manual)
        #expect(board.refresh.offeredFinalStandings?.month == FinalStandingsTests.october)
        #expect(board.refresh.offeredFinalStandings?.you?.rank == 2)
        // It opens on them; picking a Window goes back to live, until the next 1st.
        #expect(board.refresh.showsFinalStandings)
        board.refresh.showFinalStandings(false)
        #expect(!board.refresh.showsFinalStandings)
        board.refresh.showFinalStandings(true)
        #expect(board.refresh.showsFinalStandings)
        board.refresh.showFinalStandings(false)

        board.clock.date = Self.november1.addingTimeInterval(17 * 3600) // 23:00 on the 1st
        #expect(board.refresh.offeredFinalStandings != nil)
        board.clock.date = Self.november2
        #expect(board.refresh.offeredFinalStandings == nil)
        #expect(!board.refresh.showsFinalStandings)

        board.clock.date = Self.december1
        await Self.setCalendars(board.client, through: Self.december1)
        await board.refresh.refreshAll(reason: .manual)
        #expect(board.refresh.offeredFinalStandings?.month == CalendarMonth(year: 2026, month: 11))
        #expect(board.refresh.showsFinalStandings)
    }

    /// In a zone ahead of UTC, local midnight on the 1st comes before GitHub's calendar has the
    /// new day: the finished month is offered, and announced, from that midnight all the same.
    @Test func aheadOfUTCTheFinishedMonthIsOfferedFromLocalMidnightOnThe1st() async {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let tokyoMidnight = Date(timeIntervalSince1970: 1_793_460_600) // 2026-11-01T00:30+09:00
        let board = await Self.board(at: tokyoMidnight, calendar: tokyo, lastDay: "2026-10-31")
        await board.refresh.refreshAll(reason: .manual)
        #expect(board.refresh.offeredFinalStandings?.month == FinalStandingsTests.october)
        #expect(board.refresh.showsFinalStandings)
        #expect(board.spy.monthFinals.map(\.title) == ["October final"])
        #expect(board.spy.monthFinals.map(\.body) == ["You finished #2 of 3"])
    }

    /// An account that has never been announced anything (a new install, or the first version
    /// with month finals) starts quietly: its first successful refresh records last month without
    /// a notification, so it never hears old news. The next month's end is announced as usual.
    @Test func aNeverAnnouncedAccountRecordsLastMonthWithoutANotice() async {
        let announced = InMemoryAnnouncedMonthPersistence()
        let board = await Self.board(at: Self.november2, announced: announced)
        await board.refresh.refreshAll(reason: .manual)
        #expect(board.spy.monthFinals.isEmpty)
        #expect(announced.load() == ["me": "2026-10"])

        board.clock.date = Self.december1
        await Self.setCalendars(board.client, through: Self.december1)
        await board.refresh.refreshAll(reason: .manual)
        #expect(board.spy.monthFinals.map(\.title) == ["November final"])
    }

    @Test func theFirstRefreshOfANewMonthAnnouncesLastMonthOnce() async {
        let announced = Self.announcedSeptember()
        let board = await Self.board(announced: announced)
        await board.refresh.refreshAll(reason: .manual)
        #expect(board.spy.monthFinals.map(\.title) == ["October final"])
        #expect(board.spy.monthFinals.map(\.body) == ["You finished #2 of 3"])
        #expect(board.spy.monthFinals.map(\.id) == ["monthfinal.2026-10"])
        board.clock.date = Self.november2
        await board.refresh.refreshAll(reason: .manual)
        #expect(board.spy.monthFinals.count == 1)

        // A relaunch (a new coordinator over the same saved months) doesn't announce it again.
        let relaunched = await Self.board(at: Self.november2, announced: announced, store: board.store)
        await relaunched.refresh.refreshAll(reason: .manual)
        #expect(relaunched.spy.monthFinals.isEmpty)
    }

    /// Notifications off: nothing is posted, and the month still counts as announced, so turning
    /// them on later in the month doesn't bring up stale news. The Windows app does the same.
    @Test func withNotificationsOffTheMonthPassesQuietly() async throws {
        let suite = "month-final-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = NotificationService(defaults: defaults, authorize: { true })
        #expect(!notifications.isEnabled)
        #expect(!notifications.postMonthFinal(id: "monthfinal.2026-10", title: "October final", body: "You finished #2 of 3"))

        let announced = UserDefaultsAnnouncedMonthPersistence(defaults: defaults)
        announced.save(["me": "2026-09"])
        let board = await Self.board(announced: announced)
        await board.refresh.refreshAll(reason: .manual)
        #expect(UserDefaultsAnnouncedMonthPersistence(defaults: defaults).load() == ["me": "2026-10"])
    }

    /// It waits while someone with a saved calendar fails to refresh, so it never reports a place
    /// from stale numbers; people who have never loaded don't hold it back.
    @Test func aFailedRefreshOfSomeoneWithACalendarHoldsTheNoticeBack() async {
        let board = await Self.board()
        await board.refresh.refreshAll(reason: .manual)
        #expect(board.spy.monthFinals.count == 1)

        let later = await Self.board(at: Self.december1)
        later.store.updateHistories(["ana": FinalStandingsTests.history(through: "2026-11-30")])
        await later.client.setResponse(.failure(.network("offline")), for: "ana")
        await later.refresh.refreshAll(reason: .manual)
        #expect(later.spy.monthFinals.isEmpty)
        await Self.setCalendars(later.client, through: Self.december1)
        await later.refresh.refreshAll(reason: .manual)
        #expect(later.spy.monthFinals.map(\.title) == ["November final"])

        let newcomer = await Self.board()
        await newcomer.client.setResponse(.failure(.userNotFound), for: "bo")
        await newcomer.refresh.refreshAll(reason: .manual)
        #expect(newcomer.spy.monthFinals.map(\.body) == ["You finished #2 of 3"])
    }

    /// The last month announced is kept per account: another account on this device still hears
    /// its own result.
    @Test func eachAccountHearsItsOwnResult() async {
        let announced = Self.announcedSeptember(["me", "ana"])
        let first = await Self.board(announced: announced)
        await first.refresh.refreshAll(reason: .manual)
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "ana", members: ["me", "bo"])
        let second = await Self.board(announced: announced, store: store)
        await second.refresh.refreshAll(reason: .manual)
        #expect(second.spy.monthFinals.map(\.body) == ["You finished #1 of 3"])
        #expect(announced.load() == ["me": "2026-10", "ana": "2026-10"])
    }
}
