import Foundation

extension LiveRankState {
    /// The one derivation of Live rank, built on `Ranking.order`. The relay ports it
    /// (`deriveLiveRankState`), and `fixtures/ranking-conformance.json` keeps the two in step.
    ///
    /// - Parameters:
    ///   - competitors: the visible competitors in board order, you (`isSelf`) first. Every board
    ///     lists you first (`StandingsStore.addSelf`/`replaceRoster`, the relay's `selfFirst`), so
    ///     `Ranking.order` gives you every tie, which `gapToPass` relies on.
    ///   - standings: counts by login. A missing entry, or one for another Window, is no data.
    ///   - rankDeltas: today's movement by login (baseline − current); read only on Windows that
    ///     show it (`showsTodaysMovement`: Today and This month). The relay's port reads Today only
    ///     until it ranks This month (#97).
    ///   - streaks: current streak by login (`ContributionHistory.currentStreak`), for everyone
    ///     with a calendar. Yours shows only beside your count; a missing entry is no streak.
    ///   - now: when the data was fetched. Becomes `updatedAt`, rounded down to whole seconds.
    static func derive(
        competitors: [Competitor],
        standings: [String: Standing],
        window: ContributionWindow,
        rankDeltas: [String: Int],
        streaks: [String: Int] = [:],
        now: Date
    ) -> LiveRankState {
        func count(_ login: String) -> Int? {
            guard let standing = standings[login], standing.window == window else { return nil }
            return standing.contributions
        }
        func movement(_ login: String) -> Int {
            window.showsTodaysMovement ? rankDeltas[login] ?? 0 : 0
        }
        func neighbor(_ entry: Ranking.Entry?) -> Neighbor? {
            guard let login = entry?.competitor.username, let contributions = count(login) else { return nil }
            return Neighbor(login: login, contributions: contributions, movementToday: movement(login),
                            streak: streaks[login])
        }

        assert(!competitors.contains(where: \.isSelf) || competitors.first?.isSelf == true,
               "You come first on your own board: you win ties, and gapToPass relies on it")
        let ranked = Ranking.order(competitors: competitors, standings: standings, window: window)
        let me = competitors.first(where: \.isSelf)?.username
        let contributions = me.flatMap(count)
        let position = ranked.firstIndex { $0.competitor.isSelf }
        // No rank without your own count, or with nobody else on the board (never "#1 of 1").
        let ranks = contributions != nil && competitors.count > 1 ? position : nil

        return LiveRankState(
            window: window.rawValue,
            rank: ranks.map { ranked[$0].rank },
            competitorCount: competitors.count,
            contributions: contributions,
            above: ranks.flatMap { neighbor(ranked[safe: $0 - 1]) },
            below: ranks.flatMap { neighbor(ranked[safe: $0 + 1]) },
            movementToday: me.map(movement) ?? 0,
            streak: contributions == nil ? nil : me.flatMap { streaks[$0] },
            updatedAt: Int(now.timeIntervalSince1970.rounded(.down))
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
