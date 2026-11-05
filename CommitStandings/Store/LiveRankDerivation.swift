import Foundation

extension LiveRankState {
    /// The single derivation, shared with the relay through
    /// `shared/fixtures/ranking-conformance.json` (`relay/src/ranking.ts`). Pass the visible
    /// competitors in board order. A standing with `lastUpdated == .distantPast` is a
    /// placeholder (never loaded, or failed with nothing cached), so it counts as no data.
    static func derive(
        competitors: [Competitor],
        standings: [String: Standing],
        window: ContributionWindow,
        rankDeltas: [String: Int],
        now: Date
    ) -> LiveRankState {
        let visible = Set(competitors.map(\.username))
        let data = standings.filter { login, standing in
            visible.contains(login) && standing.window == window && standing.lastUpdated != .distantPast
        }
        let ranked = Ranking.order(competitors: competitors, standings: data, window: window)
        let selfIndex = ranked.firstIndex { $0.competitor.isSelf }
        let me = selfIndex.map { ranked[$0] }
        let contributions = me.flatMap { data[$0.competitor.username]?.contributions }
        let ranks = contributions != nil && competitors.count > 1

        func neighbor(at index: Int) -> Neighbor? {
            guard ranks, ranked.indices.contains(index) else { return nil }
            let login = ranked[index].competitor.username
            return data[login].map { Neighbor(login: login, contributions: $0.contributions) }
        }

        let newest = data.values.map(\.lastUpdated).max() ?? now
        return LiveRankState(
            window: window.rawValue,
            rank: ranks ? me?.rank : nil,
            competitorCount: competitors.count,
            contributions: contributions,
            above: selfIndex.flatMap { neighbor(at: $0 - 1) },
            below: selfIndex.flatMap { neighbor(at: $0 + 1) },
            movementToday: ranks && window == .daily ? (me.flatMap { rankDeltas[$0.competitor.username] } ?? 0) : 0,
            updatedAt: Int(newest.timeIntervalSince1970.rounded(.down))
        )
    }
}

extension LiveRankState {
    /// Live rank for `window` from the board as it stands: visible competitors only (hidden
    /// people are left out), and `rankDelta` as the Today board reports it
    /// (`RefreshCoordinator.rankDelta(for:)`), so Live rank never disagrees with the board.
    @MainActor
    init(store: StandingsStore, window: ContributionWindow, rankDelta: (String) -> Int?, now: Date) {
        let competitors = store.visibleCompetitors
        var deltas: [String: Int] = [:]
        if let me = store.selfCompetitor?.username { deltas[me] = rankDelta(me) }
        self = Self.derive(
            competitors: competitors,
            standings: store.standings(for: window),
            window: window,
            rankDeltas: deltas,
            now: now
        )
    }
}
