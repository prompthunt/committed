import Foundation
import Testing
@testable import CommitStandingsiOS

/// Answers each login with a calendar from mid-September to `through`, its October total on the
/// 15th; logins it doesn't know aren't found.
actor CalendarContributions: ContributionsFetching {
    private let octoberTotals: [String: Int]
    private let through: String

    init(octoberTotals: [String: Int], through: String = "2026-11-01") {
        self.octoberTotals = octoberTotals
        self.through = through
    }

    func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date)
        async -> Result<StandingCounts, ContributionsError> {
        guard let total = octoberTotals[username] else { return .failure(.userNotFound) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        var day = utc.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        var days: [String: Int] = [:]
        while ContributionHistory.key(for: day, in: utc) <= through {
            days[ContributionHistory.key(for: day, in: utc)] = 0
            day = utc.date(byAdding: .day, value: 1, to: day)!
        }
        days["2026-10-15"] = total
        let history = ContributionHistory(days: days, timeZone: .gmt)
        return .success(StandingCounts(contributions: history.total(for: window, asOf: reference), history: history))
    }
}

/// Final standings on iPhone, through `AppModel`: the Board on the 1st and the Sample board.
@MainActor
struct FinalStandingsAppTests {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private func makeModel(at date: Date, totals: [String: Int] = ["me": 30, "ada": 51, "bea": 10])
        -> AppModel {
        let services = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: "gho_test"),
            contributions: CalendarContributions(octoberTotals: totals),
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: "me", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["ada", "bea"]),
                ], updatedAt: date)
            },
            refreshInterval: 9_999,
            calendar: Self.utc,
            now: { date }
        )
        return AppModel(services: services, backgroundTime: FakeBackgroundTime())
    }

    private func summary(_ finals: FinalStandings?) -> [String] {
        (finals?.entries ?? []).map { "#\($0.rank) \($0.competitor.username)" + ($0.medal.map { " \($0)" } ?? "") }
    }

    @Test func theBoardOpensOnLastMonthsFinalStandingsOnThe1st() async {
        let model = makeModel(at: Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!)
        await model.sceneDidBecomeActive()
        let finals = model.refresh.offeredFinalStandings
        #expect(finals?.month.name == "October")
        #expect(summary(finals) == ["#1 ada gold", "#2 me silver", "#3 bea bronze"])
        #expect(finals?.statusLine == "October final · You finished #2 of 3")
        #expect(model.refresh.showsFinalStandings)

        // Hiding someone changes the finishes, as it changes the Board.
        model.store.setHidden(true, username: "ada")
        #expect(summary(model.refresh.offeredFinalStandings) == ["#1 me gold", "#2 bea silver"])

        // Picking a Window goes back to the live board.
        model.store.selectedWindow = .weekly
        await model.windowDidChange()
        #expect(!model.refresh.showsFinalStandings)
    }

    @Test func noFinalStandingsAfterThe1st() async {
        let model = makeModel(at: Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!)
        await model.sceneDidBecomeActive()
        #expect(model.refresh.offeredFinalStandings == nil)
        #expect(!model.refresh.showsFinalStandings)
        // Past months stay available for the person view.
        #expect(model.store.finalStandings(for: CalendarMonth(year: 2026, month: 10)) != nil)
    }

    /// The Sample board's made-up calendars give it last month's Final standings on the 1st.
    @Test func theSampleBoardHasFinalStandingsOnThe1st() async throws {
        let first = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let model = AppModel(services: SampleServices.make(now: { first }), backgroundTime: FakeBackgroundTime())
        await model.sceneDidBecomeActive()
        let finals = try #require(model.refresh.offeredFinalStandings)
        #expect(finals.month.name == "October")
        #expect(Set(finals.entries.map(\.competitor.username)) == Set(SampleServices.people))
        #expect(finals.entries.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(finals.entries.map(\.medal) == [.gold, .silver, .bronze, nil, nil])
        #expect(finals.entries.allSatisfy { ($0.contributions ?? 0) > 0 })
        #expect(finals.you?.competitor.username == SampleServices.owner)
        #expect(model.refresh.showsFinalStandings)
    }
}
