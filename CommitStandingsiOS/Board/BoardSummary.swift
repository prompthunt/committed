import Foundation

/// What the top of the board says about you: who you are, where you rank, your Contributions for
/// the Window, today's movement, and how fresh the numbers are. Ranks come from `Ranking.order`,
/// the same ordering as the rows below it.
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
    /// "2 to pass priya-s", Live rank's line: the gap to the person directly above you. nil in
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
        lastUpdated: Date?
    ) -> BoardSummary? {
        guard let me = competitors.first(where: \.isSelf) else { return nil }
        let entries = Ranking.order(competitors: competitors, standings: standings, window: window)
        let mine = standings[me.username].flatMap { standing in
            standing.window == window && standing.lastUpdated != .distantPast ? standing.contributions : nil
        }
        let hasRivals = entries.count > 1
        let rank = mine != nil && hasRivals
            ? entries.first(where: { $0.competitor.username == me.username })?.rank : nil
        let movement = window == .daily ? rankDelta(me.username).flatMap { $0 == 0 ? nil : $0 } : nil
        // Live rank's derivation, from counts that have loaded (as `LiveRankState.board` does), so
        // the hero and Live rank never disagree about the gap.
        let loaded = standings.filter { $0.value.lastUpdated != .distantPast }
        let live = LiveRankState.derive(competitors: competitors, standings: loaded, window: window,
                                        rankDeltas: [:], now: lastUpdated ?? .distantPast)
        return BoardSummary(
            username: me.username,
            firstName: DisplayName.firstName(from: displayName),
            rank: rank,
            competitorCount: entries.count,
            contributions: mine,
            movementToday: movement,
            passLine: rank == nil ? nil : live.passLine,
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
        if let movementToday {
            let places = movementToday.magnitude == 1 ? "place" : "places"
            parts.append("\(movementToday > 0 ? "up" : "down") \(movementToday.magnitude) \(places) today")
        }
        if let passLine { parts.append(passLine) }
        return parts.joined(separator: ", ")
    }
}
