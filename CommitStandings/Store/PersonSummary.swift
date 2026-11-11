import Foundation

/// What a person view shows for one Competitor: on a rival's view, their race with you this month
/// (the gap and who passed whom), then their month day by day with last month's beside it, their
/// streak (and longest), active days this month ("18 of 22") and their past months' finishes with
/// medals, each beside yours. Worked out from their saved calendar (`ContributionHistory`) and
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
        /// Where you finished that month, on a rival's view: "You #3". nil on your own.
        var yourRank: Int? = nil
        var id: CalendarMonth { month }

        /// You finished above them that month.
        var youWereAhead: Bool { yourRank.map { $0 < rank } ?? false }
    }

    /// Whose side of the race.
    enum Side: Equatable, Sendable {
        case you, them
    }

    /// How the race went, told by its lead. Ties put you ahead on the Board, so a level day keeps
    /// whoever led before it and only a strict lead counts as passing.
    enum Story: Equatable, Sendable {
        /// Never apart.
        case level
        /// One of you has led since the 1st.
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

        /// The story of two running totals, day 1 first.
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

    /// You against a rival over one month: this month so far, or on the 1st last month's finished
    /// race. Drawn as two running totals with the latest change of lead marked.
    struct Race: Equatable, Sendable {
        let month: CalendarMonth
        /// True on the 1st: the race is last month's, and it's over.
        let isFinal: Bool
        /// Running totals from the 1st, one per day through today (or the finished month's end).
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

    /// "You vs odile-m · November", or "… · October final" on the 1st.
    var raceTitle: String? {
        race.map { "You vs \(login) · \($0.month.name)\($0.isFinal ? " final" : "")" }
    }

    /// The gap in the Board's words: "5 to pass odile-m", "12 ahead of ezra-q", "Level with ezra-q";
    /// on the 1st, "odile-m beat you by 22" or "You beat odile-m by 12".
    var raceHeadline: String? {
        guard let race else { return nil }
        switch (race.leader, race.isFinal) {
        case (nil, _): return "Level with \(login)"
        case (.them?, false): return "\(race.gap.formatted()) to pass \(login)"
        case (.you?, false): return "\(race.gap.formatted()) ahead of \(login)"
        case (.them?, true): return "\(login) beat you by \(race.gap.formatted())"
        case (.you?, true): return "You beat \(login) by \(race.gap.formatted())"
        }
    }

    /// The headline's number, drawn in the accent: "5" in "5 to pass odile-m". nil when the
    /// headline doesn't start with it.
    var raceHeadlineNumber: String? {
        guard let race, !race.isFinal, race.leader != nil else { return nil }
        return race.gap.formatted()
    }

    /// Who passed whom: "odile-m passed you on November 8", "You've led all month".
    var raceStory: String? {
        guard let race else { return nil }
        let over = race.isFinal
        func on(_ day: Int) -> String { "\(race.month.name) \(day)" }
        switch race.story {
        case .level:
            return "Level all month"
        case .led(.you):
            return over ? "You led all month" : "You’ve led all month"
        case .led(.them):
            return over ? "\(login) led all month" : "\(login) has led all month"
        case let .pulledAhead(side, day):
            return "\(side == .you ? "You" : login) pulled ahead on \(on(day))"
        case let .passed(side, day, changes):
            let who = side == .you ? "You passed \(login)" : "\(login) passed you"
            return "\(who) on \(on(day))" + (changes > 1 ? " · the lead changed \(changes) times" : "")
        case let .caught(side, day):
            return side == .you ? "You caught \(login) on \(on(day))" : "\(login) caught you on \(on(day))"
        }
    }

    /// The race card read aloud, chart included: "You vs odile-m, November. 5 to pass odile-m.
    /// odile-m passed you on November 8. odile-m 62, you 57."
    var raceSpoken: String? {
        guard let race, let raceHeadline, let raceStory else { return nil }
        return "You vs \(login), \(race.month.name)\(race.isFinal ? " final" : ""). \(raceHeadline). \(raceStory). "
            + "\(login) \(race.theirTotal.formatted()), you \(race.yourTotal.formatted())."
    }

    /// Past months' head-to-head on a rival's view: "odile-m 2 · you 1" (months each finished
    /// above the other). nil on your own view or with no finished months.
    var recordText: String? {
        guard let finishes = days?.finishes, finishes.contains(where: { $0.yourRank != nil }) else { return nil }
        let yours = finishes.filter(\.youWereAhead).count
        let theirs = finishes.filter { $0.yourRank != nil && !$0.youWereAhead }.count
        return "\(login) \(theirs) · you \(yours)"
    }

    /// The record read aloud: "Months finished ahead: odile-m 2, you 1".
    var recordSpoken: String? {
        recordText.map { "Months finished ahead: " + $0.replacingOccurrences(of: " · ", with: ", ") }
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

    /// "October: #2 of 6, 41 contributions, silver medal, you finished #3".
    func finishSpoken(_ finish: Finish) -> String {
        "\(finishName(finish)): #\(finish.rank) of \(finish.of), \(Self.plural(finish.contributions, "contribution"))"
            + (finish.medal.map { ", \($0) medal" } ?? "")
            + (finish.yourRank.map { ", you finished #\($0)" } ?? "")
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

        let me = competitor.isSelf ? nil : selfCompetitor?.username
        let days = history.map { history in
            let thisMonth = history.dailyCounts(in: month, through: dayOfMonth)
            let finishes = finishedMonths(asOf: reference, calendar: calendar).compactMap { finished
                -> PersonSummary.Finish? in
                guard let standings = finalStandings(for: finished), let entry = standings.entry(for: login) else {
                    return nil
                }
                return PersonSummary.Finish(month: finished, rank: entry.rank, of: standings.entries.count,
                                            contributions: entry.contributions ?? 0, medal: entry.medal,
                                            yourRank: me.flatMap { standings.entry(for: $0)?.rank })
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
        var race: PersonSummary.Race?
        if let theirs = history, let me, let mine = self.history(for: me) {
            // On the 1st the new month has barely begun: show last month's finished race instead,
            // when it's on offer as Final standings.
            if dayOfMonth == 1 {
                let last = month.previous
                if finalStandings(for: last) != nil {
                    race = PersonSummary.Race(month: last, isFinal: true,
                                              yours: PersonSummary.Race.running(mine.dailyCounts(in: last)),
                                              theirs: PersonSummary.Race.running(theirs.dailyCounts(in: last)))
                }
            } else {
                race = PersonSummary.Race(month: month, isFinal: false,
                                          yours: PersonSummary.Race.running(mine.dailyCounts(in: month, through: dayOfMonth)),
                                          theirs: PersonSummary.Race.running(theirs.dailyCounts(in: month, through: dayOfMonth)))
            }
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
