import Foundation

/// What the top of the board says about you: who you are, where you rank, your Contributions for
/// the Window, today's movement, and how fresh the numbers are. It's `LiveRankState.derive` (built
/// on `Ranking.order`, the rows' ordering) plus who you are and when the numbers were fetched.
/// While the board shows a finished month's Final standings it's your result there instead
/// (`make(finals:)`), as the Mac's card shows.
struct BoardSummary: Equatable {
    let username: String
    /// Your first name from your GitHub profile, when it has one.
    let firstName: String?
    /// Your rank among the people shown, or nil when your Contributions haven't loaded or nobody
    /// else is on the board (a rank of "1 of 1" means nothing).
    let rank: Int?
    /// Everyone ranked, including you.
    let competitorCount: Int
    /// Your Contributions for the Window, or nil before they've loaded (never a fake zero).
    let contributions: Int?
    /// Places moved since the start of today (+ up, − down); Today and This month only, nil when
    /// unmoved.
    let movementToday: Int?
    /// Your current streak, on every Window. nil until your Contributions have loaded, so a failed
    /// or first load never reads as a broken streak. Shown from 2 days (`StreakLabel`).
    let streak: Int?
    /// "2 to pass odile-m", Live rank's line: the gap to the person directly above you. nil in
    /// first place, or when either count hasn't loaded.
    let passLine: String?
    let window: ContributionWindow
    /// "Day 10 of 30" on This month, nil on the other Windows.
    let dayOfMonth: String?
    /// The finished month ("October") on Final standings: `rank` and `contributions` are your
    /// finish and total there. nil on the live board.
    let period: String?
    let lastUpdated: Date?

    static func make(
        competitors: [Competitor],
        standings: [String: Standing],
        window: ContributionWindow,
        displayName: String?,
        rankDelta: (String) -> Int?,
        streak: (String) -> Int? = { _ in nil },
        lastUpdated: Date?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> BoardSummary? {
        guard let me = competitors.first(where: \.isSelf) else { return nil }
        // Live rank's derivation, from counts that have loaded (as `LiveRankState.board` does), so
        // the hero and Live rank never disagree about your rank, your count, or the gap.
        let loaded = standings.filter { $0.value.lastUpdated != .distantPast }
        var deltas: [String: Int] = [:]
        if window.showsTodaysMovement { deltas[me.username] = rankDelta(me.username) }
        let live = LiveRankState.derive(competitors: competitors, standings: loaded, window: window,
                                        rankDeltas: deltas, now: lastUpdated ?? .distantPast)
        return BoardSummary(
            username: me.username,
            firstName: DisplayName.firstName(from: displayName),
            rank: live.rank,
            competitorCount: live.competitorCount,
            contributions: live.contributions,
            movementToday: live.movementToday == 0 ? nil : live.movementToday,
            streak: live.contributions == nil ? nil : streak(me.username),
            passLine: live.passLine,
            window: window,
            dayOfMonth: window.dayOfMonth(asOf: today, calendar: calendar),
            period: nil,
            lastUpdated: lastUpdated
        )
    }

    /// Your result in a finished month's Final standings: where you finished among everyone on
    /// them and your total, with your current streak. No movement or gap: the month is over. nil
    /// when you aren't on them.
    static func make(
        finals: FinalStandings,
        displayName: String?,
        streak: (String) -> Int? = { _ in nil },
        lastUpdated: Date?
    ) -> BoardSummary? {
        guard let you = finals.you else { return nil }
        let ranked = finals.entries.count > 1 && you.contributions != nil
        return BoardSummary(
            username: you.competitor.username,
            firstName: DisplayName.firstName(from: displayName),
            rank: ranked ? you.rank : nil,
            competitorCount: finals.entries.count,
            contributions: you.contributions,
            movementToday: nil,
            streak: you.contributions == nil ? nil : streak(you.competitor.username),
            passLine: nil,
            window: .month,
            dayOfMonth: nil,
            period: finals.month.name,
            lastUpdated: lastUpdated
        )
    }

    /// One VoiceOver sentence for the whole summary.
    var accessibilityDescription: String {
        var parts = ["You, @\(username)"]
        if let rank {
            parts.append(period.map { "finished \(rank) of \(competitorCount) in \($0)" } ?? "rank \(rank) of \(competitorCount)")
        }
        if let contributions {
            parts.append("\(contributions) contributions " + (period.map { "in \($0)" } ?? "for \(window.accessibilityDescription)"))
        } else {
            parts.append("contributions not loaded yet")
        }
        if let dayOfMonth { parts.append(dayOfMonth.lowercased()) }
        if let spoken = StreakLabel.spoken(streak) { parts.append(spoken) }
        if let movementToday {
            let places = movementToday.magnitude == 1 ? "place" : "places"
            parts.append("\(movementToday > 0 ? "up" : "down") \(movementToday.magnitude) \(places) today")
        }
        if let passLine { parts.append(passLine) }
        return parts.joined(separator: ", ")
    }
}
