import Foundation

/// A calendar month as GitHub's civil days name it (`"2026-10-…"`), so a month's days are the same
/// in every time zone.
struct CalendarMonth: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    /// 1 (January) through 12.
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// The month containing `date` in `calendar` (the device's, for "this month").
    init(containing date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1)
    }

    /// The month a `"YYYY-MM-DD"` (or `"YYYY-MM"`) key belongs to.
    init?(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else {
            return nil
        }
        self.init(year: year, month: month)
    }

    static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    var previous: CalendarMonth {
        month == 1 ? CalendarMonth(year: year - 1, month: 12) : CalendarMonth(year: year, month: month - 1)
    }

    var next: CalendarMonth {
        month == 12 ? CalendarMonth(year: year + 1, month: 1) : CalendarMonth(year: year, month: month + 1)
    }

    /// 28 to 31.
    var dayCount: Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// `"2026-10"`.
    var key: String { String(ContributionHistory.key(year: year, month: month, day: 1).prefix(7)) }
    var description: String { key }

    /// "October", in English like the rest of the app.
    var name: String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August",
                     "September", "October", "November", "December"]
        return names[(month - 1) % 12]
    }
}

extension ContributionHistory {
    /// Contributions on every day of `month`; a day the calendar doesn't have adds nothing.
    func total(in month: CalendarMonth) -> Int {
        (1...month.dayCount).reduce(0) { sum, day in
            sum + (days[Self.key(year: month.year, month: month.month, day: day)] ?? 0)
        }
    }

    /// The first month this calendar covers in full: its first day's month when that's a 1st,
    /// otherwise the month after. GitHub's calendar has every day, zeros included, so its first
    /// key is the first day it covers. nil for an empty calendar.
    var firstFullMonth: CalendarMonth? {
        guard let first = days.keys.min(), let month = CalendarMonth(key: first) else { return nil }
        return first.hasSuffix("-01") ? month : month.next
    }

    /// The month of the calendar's latest day: the month it was fetched in.
    var latestMonth: CalendarMonth? {
        days.keys.max().flatMap(CalendarMonth.init(key:))
    }
}

/// Gold, silver or bronze: ranks 1 to 3 of a finished month, when that month's total is above zero.
enum Medal: Int, Codable, Sendable, CustomStringConvertible {
    case gold = 1, silver, bronze

    init?(rank: Int, contributions: Int?) {
        guard let contributions, contributions > 0 else { return nil }
        self.init(rawValue: rank)
    }

    var emoji: String {
        switch self {
        case .gold: "🥇"
        case .silver: "🥈"
        case .bronze: "🥉"
        }
    }

    var description: String {
        switch self {
        case .gold: "gold"
        case .silver: "silver"
        case .bronze: "bronze"
        }
    }
}

/// A finished month's ranks among the people currently on your board: the board's own ranking
/// (`Ranking.order`, so you win ties) over each person's total for that month, with a medal for
/// ranks 1 to 3 above zero. Worked out from saved calendars whenever it's asked for, never frozen,
/// so hiding or showing someone changes it the way it changes the Board. The Windows core's
/// `finishes` follows the same rules.
struct FinalStandings: Equatable, Sendable {
    struct Entry: Identifiable, Equatable, Sendable {
        let rank: Int
        let competitor: Competitor
        /// The month's total, or nil when there's no saved calendar for this person: they rank
        /// last and never get a medal.
        let contributions: Int?
        let medal: Medal?
        var id: UUID { competitor.id }
    }

    let month: CalendarMonth
    let entries: [Entry]

    /// `competitors` in board order (you first), ranked by their `month` totals from `histories`.
    init(month: CalendarMonth, competitors: [Competitor], histories: [String: ContributionHistory]) {
        var totals: [String: Int] = [:]
        var standings: [String: Standing] = [:]
        for competitor in competitors {
            guard let history = histories[competitor.username] else { continue }
            let total = history.total(in: month)
            totals[competitor.username] = total
            standings[competitor.username] = Standing(
                username: competitor.username, contributions: total, window: .month,
                lastUpdated: .distantFuture, state: .loaded
            )
        }
        self.month = month
        entries = Ranking.order(competitors: competitors, standings: standings, window: .month).map { entry in
            let total = totals[entry.competitor.username]
            return Entry(rank: entry.rank, competitor: entry.competitor, contributions: total,
                         medal: Medal(rank: entry.rank, contributions: total))
        }
    }

    /// Your place, if you're on the board.
    var you: Entry? { entries.first { $0.competitor.isSelf } }

    func entry(for login: String) -> Entry? { entries.first { $0.competitor.username == login } }

    /// "October final" / "You finished #2 of 8": the Leaderboard Notification, and the Board's line
    /// over the rows. nil without you on the board.
    var result: (title: String, body: String)? {
        guard let you else { return nil }
        return ("\(month.name) final", "You finished #\(you.rank) of \(entries.count)")
    }
}
