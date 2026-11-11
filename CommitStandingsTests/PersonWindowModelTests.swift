import Testing
import Foundation
@testable import CommitStandings

/// Which person the Mac's person window shows (#102). Clicking a row on the board shows that
/// person; the one window then switches to whoever was clicked last, and follows the board as
/// their counts load or they leave it.
@MainActor
struct PersonWindowModelTests {
    static let now = PersonSummaryTests.noon("2026-11-22")

    static func model(_ store: StandingsStore) -> PersonWindowModel {
        PersonWindowModel(store: store, now: { now }, calendar: PersonSummaryTests.utc)
    }

    static func board() -> StandingsStore {
        PersonSummaryTests.store(rivals: ["ana", "ben"], histories: [
            "me": PersonSummaryTests.history(through: "2026-11-22", [:]),
            "ana": PersonSummaryTests.ana,
            "ben": PersonSummaryTests.history(through: "2026-11-22", ["2026-11-22": 2]),
        ])
    }

    @Test func showsNobodyUntilARowIsClicked() {
        #expect(Self.model(Self.board()).shown == nil)
    }

    @Test func clickingARowShowsThatPersonsMonth() throws {
        let model = Self.model(Self.board())
        model.show("ana")
        let shown = try #require(model.shown)
        #expect(shown.login == "ana")
        #expect(shown.days?.activeDays == 5)
        #expect(shown.dayOfMonth == 22)
    }

    @Test func clickingAnotherPersonSwitchesTheWindowToThem() {
        let model = Self.model(Self.board())
        model.show("ana")
        model.show("ben")
        #expect(model.shown?.login == "ben")
        // Clicking the person already shown keeps them (the opener only brings the window forward).
        model.show("ben")
        #expect(model.shown?.login == "ben")
    }

    @Test func yourOwnRowShowsYourView() {
        let model = Self.model(Self.board())
        model.show("me")
        #expect(model.shown?.isYou == true)
    }

    @Test func someoneWhoseCountHasNotLoadedShowsWaitingThenTheirMonth() throws {
        let store = Self.board()
        try store.addRival(username: "cat")
        let model = Self.model(store)
        model.show("cat")
        #expect(model.shown?.status == .loading)
        #expect(model.shown?.days == nil)

        store.updateHistories(["cat": PersonSummaryTests.history(through: "2026-11-22", ["2026-11-21": 1, "2026-11-22": 4])])
        #expect(model.shown?.status == .loaded)
        #expect(model.shown?.days?.currentStreak == 2)
    }

    @Test func someoneHiddenFromTheBoardLeavesTheWindowEmpty() {
        let store = Self.board()
        let model = Self.model(store)
        model.show("ana")
        store.setHidden(true, username: "ana")
        #expect(model.shown == nil)
        store.setHidden(false, username: "ana")
        #expect(model.shown?.login == "ana")
    }
}
