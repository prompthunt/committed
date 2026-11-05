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
    ///   - rankDeltas: today's movement by login (baseline − current); read only on Today.
    ///   - now: when the data was fetched. Becomes `updatedAt`, rounded down to whole seconds.
    static func derive(
        competitors: [Competitor],
        standings: [String: Standing],
        window: ContributionWindow,
        rankDeltas: [String: Int],
        now: Date
    ) -> LiveRankState {
        func count(_ login: String) -> Int? {
            guard let standing = standings[login], standing.window == window else { return nil }
            return standing.contributions
        }
        func neighbor(_ entry: Ranking.Entry?) -> Neighbor? {
            guard let login = entry?.competitor.username, let contributions = count(login) else { return nil }
            return Neighbor(login: login, contributions: contributions)
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
            movementToday: window == .daily ? me.flatMap { rankDeltas[$0] } ?? 0 : 0,
            updatedAt: Int(now.timeIntervalSince1970.rounded(.down))
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension LiveRankState {
    /// Live rank for `window` from the board as it stands, so it never disagrees with the board:
    /// visible competitors only, and a row still loading for the first time (or failed with nothing
    /// cached, both `.distantPast`) counts as no data rather than a zero. `rankDelta` is the
    /// Today board's movement (`RefreshCoordinator.rankDelta(for:)`). `updatedAt` is the newest
    /// count shown, or `now` when there's none.
    @MainActor
    static func board(
        _ store: StandingsStore,
        window: ContributionWindow,
        rankDelta: (String) -> Int?,
        now: Date
    ) -> LiveRankState {
        let competitors = store.visibleCompetitors
        let visible = Set(competitors.map(\.username))
        let standings = store.standings(for: window).filter { login, standing in
            visible.contains(login) && standing.lastUpdated != .distantPast
        }
        var deltas: [String: Int] = [:]
        if let me = store.selfCompetitor?.username { deltas[me] = rankDelta(me) }
        return derive(
            competitors: competitors,
            standings: standings,
            window: window,
            rankDeltas: deltas,
            now: standings.values.map(\.lastUpdated).max() ?? now
        )
    }
}
