import Foundation
import Testing
@testable import CommitStandingsiOS

/// The person view on iPhone, through `AppModel`: tapping someone on the Board shows their month,
/// on the Sample board too, and closes when they leave the board.
@MainActor
struct PersonViewAppTests {
    /// November 10, 2026, noon on this device: inside the 8th–29th, where the Sample board's
    /// This month totals are fixed.
    nonisolated static let november10: Date = Calendar.current.date(
        from: DateComponents(year: 2026, month: 11, day: 10, hour: 12)
    )!

    /// Kept for the model's lifetime: its publisher only borrows it.
    let widgets = RecordingWidgets()

    private func sampleBoard() async -> AppModel {
        let notConnected = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: nil)
        )
        let now: @Sendable () -> Date = { Self.november10 }
        let model = AppModel(
            services: notConnected,
            sampleServices: { SampleServices.make(now: now) },
            backgroundTime: FakeBackgroundTime(),
            liveRankActivities: FakeLiveRankActivities(),
            widgets: widgets.publisher,
            now: now
        )
        await model.startSampleBoard()
        return model
    }

    @Test func tappingSomeoneOnTheSampleBoardShowsTheirMonth() async throws {
        let model = await sampleBoard()
        model.showPerson("ines-volk")
        let ines = try #require(model.shownPerson)
        let days = try #require(ines.days)
        #expect(ines.login == "ines-volk")
        #expect(ines.dayOfMonth == 10)
        #expect(days.thisMonth.count == 10)
        // The same 84 the Board shows on This month.
        #expect(days.thisMonth.reduce(0, +) == 84)
        #expect(days.lastMonth.count == 31)
        #expect(days.currentStreak == 47)
        #expect(days.activeDays == 10) // a 47-day streak covers the whole month so far
        #expect(ines.activeDaysText == "10 of 10")
    }

    @Test func theSampleBoardsStreaksReadInDays() async throws {
        let model = await sampleBoard()
        let streaks = SampleServices.people.map { login -> String in
            model.showPerson(login)
            return "\(login) \(model.shownPerson?.days.map { PersonSummary.streakText($0.currentStreak) } ?? "waiting")"
        }
        #expect(streaks == ["ines-volk 47 days", "odile-m 365+ days", "ezra-q 3 days", "ari-linden 14 days", "bram-ott 0 days"])
        model.showPerson("odile-m")
        #expect(model.shownPerson?.days?.longestStreak == 371)
    }

    @Test func theSampleBoardHasPastMonthsWithOneGoldEach() async throws {
        let model = await sampleBoard()
        var golds: [CalendarMonth: [String]] = [:]
        for login in SampleServices.people {
            model.showPerson(login)
            let finishes = try #require(model.shownPerson?.days?.finishes)
            // December 2025 (the calendar's first full month) through October, newest first.
            #expect(finishes.first?.month == CalendarMonth(year: 2026, month: 10))
            #expect(finishes.last?.month == CalendarMonth(year: 2025, month: 12))
            #expect(finishes.count == 11)
            #expect(finishes.allSatisfy { $0.of == 5 })
            for finish in finishes where finish.medal == .gold { golds[finish.month, default: []].append(login) }
        }
        #expect(golds.count == 11)
        #expect(golds.values.allSatisfy { $0.count == 1 })
    }

    @Test func everyPastMonthInThePersonViewCanBeShared() async throws {
        let model = await sampleBoard()
        model.showPerson("ines-volk")
        let finishes = try #require(model.shownPerson?.days?.finishes)
        #expect(!finishes.isEmpty)
        #expect(finishes.allSatisfy { model.finalStandingsToShare(for: $0.month) != nil })
        // A month before your calendar's first full month isn't shared.
        #expect(model.finalStandingsToShare(for: CalendarMonth(year: 2025, month: 10)) == nil)
    }

    @Test func yourOwnViewIsMarkedAsYours() async throws {
        let model = await sampleBoard()
        model.showPerson(SampleServices.owner)
        #expect(model.shownPerson?.isYou == true)
        model.showPerson("ezra-q")
        #expect(model.shownPerson?.isYou == false)
    }

    @Test func hidingThePersonShownClosesTheirView() async throws {
        let model = await sampleBoard()
        model.showPerson("ezra-q")
        #expect(model.shownPerson != nil)
        model.store.setHidden(true, username: "ezra-q")
        #expect(model.shownPerson == nil)
    }

    @Test func leavingTheSampleBoardForgetsWhoWasShown() async throws {
        let model = await sampleBoard()
        model.showPerson("ezra-q")
        await model.leaveSampleBoard()
        #expect(model.selectedPerson == nil)
        #expect(model.shownPerson == nil)
    }
}
