import Foundation
import Observation

/// Who the Mac's person window shows. Clicking a row on the board calls `show(_:)`, then opens
/// the window (`PersonWindow.open`); there is one window, so it switches to whoever was clicked
/// last, and clicking the person already shown just brings it forward. `shown` is worked out on
/// each read, so the window follows the board as their counts load.
@MainActor @Observable
final class PersonWindowModel {
    private(set) var login: String?
    @ObservationIgnored private let store: StandingsStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    init(store: StandingsStore, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    func show(_ login: String) {
        self.login = login
    }

    /// The window's content as of now, or nil: nobody clicked yet.
    var shown: PersonSummary? {
        login.flatMap { store.person($0, asOf: now(), calendar: calendar) }
    }
}
