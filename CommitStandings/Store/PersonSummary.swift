import Foundation

/// What a person view shows for one Competitor: on a rival's view, their race with you over the
/// Board's 30 days (the gap and who passed whom), then their month day by day with last month's
/// beside it, their streak (and longest) and active days this month ("18 of 22"). Worked out from
/// their saved calendar (`ContributionHistory`). The iPhone sheet or pane and the Mac window draw
/// it with `PersonViewContent`; the Windows core's `BoardCore::person` follows the same rules.
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
    }

    /// Whose side of the race.
    enum Side: Equatable, Sendable {
        case you, them
    }

    /// How the race went, told by its lead. Ties put you ahead on the Board, so a level day keeps
    /// whoever led before it and only a strict lead counts as passing. Days are 1-based positions
    /// in the race (`Race.dates`).
    enum Story: Equatable, Sendable {
        /// Never apart.
        case level
        /// One of you has led since the first day.
        case led(Side)
        /// Level at first, then one pulled ahead on `day` and has led since.
        case pulledAhead(Side, day: Int)
        /// The lead changed hands `changes` times; `Side` took it last, on `day`.
        case passed(Side, day: Int, changes: Int)
        /// Level now: `Side` drew level on `day`, after the other had led.
        case caught(Side, day: Int)

        /// The day the chart marks: the latest pass, pull ahead or catch. nil when nothing changed.
        var day: Int? {
            switch self {
            case .level, .led: nil
            case let .pulledAhead(_, day), let .passed(_, day, _), let .caught(_, day): day
            }
        }

        var side: Side? {
            switch self {
            case .level: nil
            case let .led(side), let .pulledAhead(side, _), let .passed(side, _, _), let .caught(side, _): side
            }
        }

        /// The story of two running totals, the first day first. The Windows core's
        /// `history::race_story` follows the same rules.
        static func of(yours: [Int], theirs: [Int]) -> Story {
            let days = min(yours.count, theirs.count)
            func leader(_ i: Int) -> Side? {
                theirs[i] > yours[i] ? .them : yours[i] > theirs[i] ? .you : nil
            }
            var leading: Side?
            var firstLead = 0
            var changes = 0
            var lastChange = 0
            for i in 0..<days {
                guard let side = leader(i) else { continue }
                if leading == nil {
                    leading = side
                    firstLead = i + 1
                } else if side != leading {
                    leading = side
                    changes += 1
                    lastChange = i + 1
                }
            }
            guard let leading else { return .level }
            if days > 0, leader(days - 1) == nil {
                var start = days
                while start > 1, leader(start - 2) == nil { start -= 1 }
                return .caught(leading == .you ? .them : .you, day: start)
            }
            if changes > 0 { return .passed(leading, day: lastChange, changes: changes) }
            return firstLead == 1 ? .led(leading) : .pulledAhead(leading, day: firstLead)
        }
    }

    /// You against a rival over the Board's 30 days, through today: the same totals the Board
    /// ranks on 30 days, drawn as two running totals with the latest change of lead marked.
    struct Race: Equatable, Sendable {
        /// Each raced day, oldest first: "October 12" … today.
        let dates: [String]
        /// Running totals from the first day, one per day.
        let yours: [Int]
        let theirs: [Int]

        var story: Story { .of(yours: yours, theirs: theirs) }
        var yourTotal: Int { yours.last ?? 0 }
        var theirTotal: Int { theirs.last ?? 0 }
        /// How far apart you are now.
        var gap: Int { abs(theirTotal - yourTotal) }
        /// Who's ahead now, nil when level.
        var leader: Side? { theirTotal > yourTotal ? .them : yourTotal > theirTotal ? .you : nil }

        static func running(_ days: [Int]) -> [Int] {
            var total = 0
            return days.map { total += $0; return total }
        }
    }

    let competitor: Competitor
    let status: Status
    /// This month, and today's day of it (the 22 in "18 of 22").
    let month: CalendarMonth
    let dayOfMonth: Int
    /// nil until their calendar loads.
    let days: Days?
    /// Your race with them, on a rival's view once both your calendars load. nil on your own view.
    var race: Race? = nil

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

    /// The streak tile's value: "14 days", or "None" once it's broken.
    static func streakValue(_ current: Int) -> String {
        current == 0 ? "None" : streakText(current)
    }

    /// The streak tile's caption: their longest only when it differs from the current one, so the
    /// tile never says the same thing twice. "Best 24 days", "Longest in the past year".
    static func streakCaption(current: Int, longest: Int) -> String {
        if longest == 0 { return "No streaks in the past year" }
        if current >= longest || min(current, longest) > StreakLabel.cap { return "Longest in the past year" }
        return "Best \(streakText(longest))"
    }

    /// The streak tile read aloud: "14 days, best 24 days".
    static func streakSpoken(current: Int, longest: Int) -> String {
        let value = current == 0 ? "None" : StreakLabel.spokenDays(current)
        if longest == 0 || current >= longest || min(current, longest) > StreakLabel.cap {
            return "\(value), \(streakCaption(current: current, longest: longest).lowercased())"
        }
        return "\(value), best \(StreakLabel.spokenDays(longest))"
    }

    // MARK: Race copy

    /// "You vs odile-m · 30 days".
    var raceTitle: String? {
        race.map { _ in "You vs \(login) · \(ContributionWindow.monthly.shortTitle)" }
    }

    /// The gap in the Board's words: "5 to pass odile-m", "12 ahead of ezra-q", "Level with ezra-q".
    var raceHeadline: String? {
        guard let race else { return nil }
        switch race.leader {
        case nil: return "Level with \(login)"
        case .them?: return "\(race.gap.formatted()) to pass \(login)"
        case .you?: return "\(race.gap.formatted()) ahead of \(login)"
        }
    }

    /// The headline's number, drawn in the data color: "5" in "5 to pass odile-m".
    var raceHeadlineNumber: String? {
        guard let race, race.leader != nil else { return nil }
        return race.gap.formatted()
    }

    /// Who passed whom: "odile-m passed you on November 8", "You’ve led for all 30 days".
    var raceStory: String? {
        guard let race else { return nil }
        let span = "all \(race.dates.count) days"
        func on(_ day: Int) -> String { race.dates[safe: day - 1] ?? "day \(day)" }
        switch race.story {
        case .level:
            return "Level for \(span)"
        case .led(.you):
            return "You’ve led for \(span)"
        case .led(.them):
            return "\(login) has led for \(span)"
        case let .pulledAhead(side, day):
            return "\(side == .you ? "You" : login) pulled ahead on \(on(day))"
        case let .passed(side, day, changes):
            let who = side == .you ? "You passed \(login)" : "\(login) passed you"
            return "\(who) on \(on(day))" + (changes > 1 ? " · the lead changed \(changes) times" : "")
        case let .caught(side, day):
            return side == .you ? "You caught \(login) on \(on(day))" : "\(login) caught you on \(on(day))"
        }
    }

    /// The race card read aloud, chart included: "You vs odile-m, 30 days. 5 to pass odile-m.
    /// odile-m passed you on November 8. odile-m 62, you 57."
    var raceSpoken: String? {
        guard let race, let raceHeadline, let raceStory else { return nil }
        return "You vs \(login), \(ContributionWindow.monthly.shortTitle). \(raceHeadline). \(raceStory). "
            + "\(login) \(race.theirTotal.formatted()), you \(race.yourTotal.formatted())."
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
    /// Each day's count over `window` as of `reference`, oldest first, in this history's time
    /// zone: the days the Board sums for that Window.
    func dailyCounts(in window: ContributionWindow, asOf reference: Date) -> [Int] {
        Self.dates(in: days(in: window, asOf: reference), calendar: calendar).map {
            days[Self.key(for: $0, in: calendar)] ?? 0
        }
    }

    /// The start of each day in `range`, oldest first.
    static func dates(in range: ClosedRange<Date>, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: range.lowerBound)
        while day <= range.upperBound {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

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
    /// month and today come from their calendar's own time zone (the one the Board's Windows use),
    /// or `calendar` (the device's) before it loads.
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
            return PersonSummary.Days(
                thisMonth: thisMonth,
                lastMonth: history.dailyCounts(in: month.previous),
                currentStreak: history.currentStreak(asOf: reference),
                longestStreak: history.longestStreak(asOf: reference),
                activeDays: thisMonth.filter { $0 > 0 }.count
            )
        }
        // A rival's view races them against you over the Board's 30 days, in your calendar's days.
        var race: PersonSummary.Race?
        if !competitor.isSelf, let theirs = history, let me = selfCompetitor?.username,
           let mine = self.history(for: me) {
            let dates = ContributionHistory.dates(in: mine.days(in: .monthly, asOf: reference), calendar: mine.calendar)
            race = PersonSummary.Race(
                dates: dates.map {
                    "\(CalendarMonth(containing: $0, in: mine.calendar).name) \(mine.calendar.component(.day, from: $0))"
                },
                yours: PersonSummary.Race.running(mine.dailyCounts(in: .monthly, asOf: reference)),
                theirs: PersonSummary.Race.running(theirs.dailyCounts(in: .monthly, asOf: reference))
            )
        }
        return PersonSummary(competitor: competitor, status: status, month: month, dayOfMonth: dayOfMonth,
                             days: days, race: race)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
