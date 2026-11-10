import Foundation

/// The widgets' own refresh: every 15 minutes WidgetKit asks for a new timeline, and the widget
/// extension re-reads everyone's public contribution graph, re-ranks the board the app last saved,
/// and saves the result back to the App Group. Like the app, it reads `github.com/users/<name>/
/// contributions` anonymously: no token, no Committed relay. WidgetKit spends reloads from a daily
/// budget (about 40 to 70 for a widget you look at often), so 15 minutes is the most often it can
/// happen; iOS may stretch it. The widgets show how old their numbers are, counting up, so a
/// stretched refresh shows rather than hides.
///
/// The Sample board, and a snapshot from a build that didn't save the board's people, are never
/// refetched: they show what the app wrote.
struct WidgetRefresh: Sendable {
    /// How often the widgets ask for a new timeline.
    static let interval: TimeInterval = 15 * 60
    /// Numbers this fresh came from the app or another widget a moment ago: use them, don't fetch.
    static let reuseWithin: TimeInterval = 5 * 60
    /// At most this many contribution pages at once.
    static let concurrency = 6
    /// A refresh gives up on whatever hasn't answered by then, keeping those people's last counts.
    static let budget: TimeInterval = 20

    let fetcher: any ContributionsFetching
    var load: @Sendable () -> WidgetSnapshot? = { WidgetSnapshot.load() }
    var save: @Sendable (WidgetSnapshot) -> Void = { try? $0.save() }

    /// The snapshot to show now: refreshed from GitHub when it's due and can be, otherwise as
    /// saved. nil when the app hasn't written one (not connected).
    func current(now: Date = .now, calendar: Calendar = .current) async -> WidgetSnapshot? {
        guard let saved = load() else { return nil }
        guard saved.isSampleBoard != true,
              let people = saved.people, !people.isEmpty,
              let window = saved.state.contributionWindow,
              now.timeIntervalSince(saved.state.updatedDate) >= Self.reuseWithin
        else { return saved }
        let counts = await fetch(people, window: window, now: now)
        // Nobody answered (offline, GitHub down): keep the saved numbers, so the age keeps counting.
        guard !counts.isEmpty else { return saved }
        // The app saved newer numbers while these were loading: they win.
        if let latest = load(), latest.state.updatedAt > saved.state.updatedAt { return latest }
        let refreshed = saved.refreshed(counts: counts, now: now, calendar: calendar)
        save(refreshed)
        return refreshed
    }

    /// Everyone's count for `window`, at most `concurrency` at a time, within `budget`. Anyone who
    /// failed or didn't answer in time is left out.
    private func fetch(_ people: [String], window: ContributionWindow, now: Date) async -> [String: Int] {
        let deadline = Date().addingTimeInterval(Self.budget)
        let fetcher = fetcher
        return await withTaskGroup(of: (String, Int?).self) { group in
            var pending = people[...]
            func next(_ login: String) {
                group.addTask {
                    let result = await fetcher.standingCounts(for: login, window: window, asOf: now)
                    return (login, try? result.get().contributions)
                }
            }
            for login in pending.prefix(Self.concurrency) { next(login) }
            pending = pending.dropFirst(Self.concurrency)
            var counts: [String: Int] = [:]
            while let (login, count) = await group.next() {
                if let count { counts[login] = count }
                if Date() >= deadline {
                    group.cancelAll()
                    break
                }
                if let login = pending.popFirst() { next(login) }
            }
            return counts
        }
    }
}
