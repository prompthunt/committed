import Foundation

/// What the top of the board says about you: who you are, where you rank, your Contributions for
/// the Window, today's movement, and how fresh the numbers are. It's `LiveRankState.derive` (built
/// on `Ranking.order`, the rows' ordering) plus who you are and when the numbers were fetched.
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
    /// Places moved since the start of today (+ up, − down); Today only, nil when unmoved.
    let movementToday: Int?
    /// Your current streak, on every Window. nil until your Contributions have loaded, so a failed
    /// or first load never reads as a broken streak. Shown from 2 days (`StreakLabel`).
    let streak: Int?
    /// "2 to pass odile-m", Live rank's line: the gap to the person directly above you. nil in
    /// first place, or when either count hasn't loaded.
    let passLine: String?
    let window: ContributionWindow
    let lastUpdated: Date?

    static func make(
        competitors: [Competitor],
        standings: [String: Standing],
        window: ContributionWindow,
        displayName: String?,
        rankDelta: (String) -> Int?,
        streak: (String) -> Int? = { _ in nil },
        lastUpdated: Date?
    ) -> BoardSummary? {
        guard let me = competitors.first(where: \.isSelf) else { return nil }
        // Live rank's derivation, from counts that have loaded (as `LiveRankState.board` does), so
        // the hero and Live rank never disagree about your rank, your count, or the gap.
        let loaded = standings.filter { $0.value.lastUpdated != .distantPast }
        var deltas: [String: Int] = [:]
        if window == .daily { deltas[me.username] = rankDelta(me.username) }
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
            lastUpdated: lastUpdated
        )
    }

    /// One VoiceOver sentence for the whole summary.
    var accessibilityDescription: String {
        var parts = ["You, @\(username)"]
        if let rank { parts.append("rank \(rank) of \(competitorCount)") }
        if let contributions {
            parts.append("\(contributions) contributions for \(window.accessibilityDescription)")
        } else {
            parts.append("contributions not loaded yet")
        }
        if let spoken = StreakLabel.spoken(streak) { parts.append(spoken) }
        if let movementToday {
            let places = movementToday.magnitude == 1 ? "place" : "places"
            parts.append("\(movementToday > 0 ? "up" : "down") \(movementToday.magnitude) \(places) today")
        }
        if let passLine { parts.append(passLine) }
        return parts.joined(separator: ", ")
    }
}
