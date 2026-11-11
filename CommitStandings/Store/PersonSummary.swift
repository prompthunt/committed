import Foundation

/// What a person view shows for one Competitor: their month day by day with last month's beside
/// it, their current and longest streaks, active days this month ("18 of 22") and their past
/// months' finishes with medals. Worked out from their saved calendar (`ContributionHistory`) and
/// the Final standings of each finished month, so it agrees with the Board. The iPhone sheet or
/// pane and the Mac window draw it with `PersonViewContent`; the Windows core's
/// `BoardCore::person` follows the same rules.
///
/// Before their calendar loads, `days` is nil: the view says it's waiting rather than drawing
/// zeros.
struct PersonSummary: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// Their count is loaded (or saved, with nothing failing).
        case loaded
        /// No count yet: the first load is still to come.
        case loading
        /// GitHub didn't answer the last refresh; any saved days still show.
        case failed
    }

    /// Their place in one finished month among the people on the board now.
    struct Finish: Identifiable, Equatable, Sendable {
        let month: CalendarMonth
        let rank: Int
        /// How many people that month was ranked among: "#3 of 8".
        let of: Int
        let contributions: Int
        let medal: Medal?
        var id: CalendarMonth { month }
    }

    /// The loaded part: everything drawn from their calendar.
    struct Days: Equatable, Sendable {
        /// Each day's count from the 1st through today.
        let thisMonth: [Int]
        /// Each day's count for every day of last month (the grey bars).
        let lastMonth: [Int]
        let currentStreak: Int
        /// The longest run in the calendar, about the past year.
        let longestStreak: Int
        /// Days this month with a contribution: the 18 in "18 of 22".
        let activeDays: Int
        /// Every finished month offered as Final standings, newest first.
        let finishes: [Finish]
    }

    let competitor: Competitor
    let status: Status
    /// This month, and today's day of it (the 22 in "18 of 22").
    let month: CalendarMonth
    let dayOfMonth: Int
    /// nil until their calendar loads.
    let days: Days?

    var login: String { competitor.username }
    var isYou: Bool { competitor.isSelf }
    var lastMonth: CalendarMonth { month.previous }
    var daysInMonth: Int { month.dayCount }

    var profileURL: URL { URL(string: "https://github.com/\(login)")! }

    // MARK: Copy

    /// "18 of 22".
    var activeDaysText: String? {
        days.map { "\($0.activeDays) of \(dayOfMonth)" }
    }

    /// The person view's streak stats read in days; past GitHub's year it's "365+ days", read
    /// aloud as `StreakLabel.spokenDays`.
    static func streakText(_ days: Int) -> String {
        days > StreakLabel.cap ? "\(StreakLabel.cap)+ days" : plural(days, "day")
    }

    /// "18 active days this month, most on November 8 with 41": the chart's VoiceOver summary.
    var chartSummary: String? {
        guard let days else { return nil }
        guard days.activeDays > 0, let most = days.thisMonth.max(),
              let index = days.thisMonth.firstIndex(of: most) else { return "No contributions yet this month" }
        return "\(Self.plural(days.activeDays, "active day")) this month, most on \(month.name) \(index + 1) with \(most.formatted())"
    }

    /// One bar for VoiceOver: "November 8" / "41 contributions. October 8: 12". nil after today.
    func bar(day: Int) -> (label: String, value: String)? {
        guard let days, days.thisMonth.indices.contains(day - 1) else { return nil }
        var value = Self.plural(days.thisMonth[day - 1], "contribution")
        if days.lastMonth.indices.contains(day - 1) {
            value += ". \(lastMonth.name) \(day): \(days.lastMonth[day - 1].formatted())"
        }
        return ("\(month.name) \(day)", value)
    }

    /// The selected bar's caption: "November 8 · 41 contributions".
    func selectedDayText(_ day: Int) -> String? {
        guard let count = days?.thisMonth[safe: day - 1] else { return nil }
        return "\(month.name) \(day) · \(Self.plural(count, "contribution"))"
    }

    /// Last month's same day beside it: "October 8 · 12". nil past last month's end.
    func selectedDayComparison(_ day: Int) -> String? {
        guard let count = days?.lastMonth[safe: day - 1] else { return nil }
        return "\(lastMonth.name) \(day) · \(count.formatted())"
    }

    /// "October", or "December 2025" for a month in another year than this one.
    func finishName(_ finish: Finish) -> String {
        finish.month.year == month.year ? finish.month.name : "\(finish.month.name) \(finish.month.year)"
    }

    /// "October: #2 of 6, 41 contributions, silver medal".
    func finishSpoken(_ finish: Finish) -> String {
        "\(finishName(finish)): #\(finish.rank) of \(finish.of), \(Self.plural(finish.contributions, "contribution"))"
            + (finish.medal.map { ", \($0) medal" } ?? "")
    }

    var waitingTitle: String { "Waiting for \(login)’s count" }

    var waitingDetail: String {
        status == .failed
            ? "GitHub didn’t answer the last refresh. Committed tries again on the next one."
            : "Their month appears once the next refresh loads it."
    }

    static func plural(_ count: Int, _ word: String) -> String {
        "\(count.formatted()) \(word)\(count == 1 ? "" : "s")"
    }
}

extension ContributionHistory {
    /// Each day's count in `month`, the 1st first: every day of it, or through `last` (a day number)
    /// when given. A day the calendar doesn't have reads 0.
    func dailyCounts(in month: CalendarMonth, through last: Int? = nil) -> [Int] {
        let end = min(last ?? month.dayCount, month.dayCount)
        guard end >= 1 else { return [] }
        return (1...end).map { days[Self.key(year: month.year, month: month.month, day: $0)] ?? 0 }
    }
}

extension StandingsStore {
    /// `login`'s person view as of `reference`, or nil for anyone hidden or not on the board. This
    /// month and today come from their calendar's own time zone (the one the Board's This month
    /// uses), or `calendar` (the device's) before it loads.
    func person(_ login: String, asOf reference: Date, calendar: Calendar) -> PersonSummary? {
        guard let competitor = visibleCompetitors.first(where: { $0.username == login }) else { return nil }
        let history = history(for: login)
        let dayCalendar = history?.calendar ?? calendar
        let month = CalendarMonth(containing: reference, in: dayCalendar)
        let dayOfMonth = dayCalendar.component(.day, from: reference)

        let status: PersonSummary.Status
        if case .failed = standing(for: login, window: selectedWindow)?.state {
            status = .failed
        } else {
            status = history == nil ? .loading : .loaded
        }

        let days = history.map { history in
            let thisMonth = history.dailyCounts(in: month, through: dayOfMonth)
            let finishes = finishedMonths(asOf: reference, calendar: calendar).compactMap { finished
                -> PersonSummary.Finish? in
                guard let standings = finalStandings(for: finished), let entry = standings.entry(for: login) else {
                    return nil
                }
                return PersonSummary.Finish(month: finished, rank: entry.rank, of: standings.entries.count,
                                            contributions: entry.contributions ?? 0, medal: entry.medal)
            }
            return PersonSummary.Days(
                thisMonth: thisMonth,
                lastMonth: history.dailyCounts(in: month.previous),
                currentStreak: history.currentStreak(asOf: reference),
                longestStreak: history.longestStreak(asOf: reference),
                activeDays: thisMonth.filter { $0 > 0 }.count,
                finishes: finishes
            )
        }
        return PersonSummary(competitor: competitor, status: status, month: month, dayOfMonth: dayOfMonth, days: days)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
