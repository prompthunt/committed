import Foundation

// The app builds this snapshot from its current board.
extension WidgetSnapshot {
    /// The snapshot for the visible board, ranked as the Board ranks it, with the first `rows`
    /// people (the large widget's six; the share images take more), and everyone's streak.
    @MainActor
    static func board(
        _ store: StandingsStore,
        window: ContributionWindow,
        rankDelta: (String) -> Int?,
        now: Date,
        rows: Int = topCount
    ) -> WidgetSnapshot? {
        guard let me = store.selfCompetitor?.username else { return nil }
        let state = LiveRankState.board(store, window: window, rankDelta: rankDelta, now: now)
        let competitors = store.visibleCompetitors
        let visible = Set(competitors.map(\.username))
        let standings = store.standings(for: window).filter { login, standing in
            visible.contains(login) && standing.lastUpdated != .distantPast
        }
        let ranked = Ranking.order(competitors: competitors, standings: standings, window: window)
        // The streaks Live rank's state carries, from the same saved calendars as of `now`.
        let streaks = store.streaks(asOf: now)
        let board = ranked.map { entry in
            let login = entry.competitor.username
            let standing = standings[login]
            let contributions = standing?.window == window ? standing?.contributions : nil
            return Row(
                rank: entry.rank,
                login: login,
                contributions: contributions,
                movement: window.showsTodaysMovement ? rankDelta(login) ?? 0 : 0,
                isSelf: entry.competitor.isSelf,
                // A streak follows its count, as on the Board.
                streak: contributions == nil ? nil : streaks[login]
            )
        }
        return WidgetSnapshot(selfLogin: me, state: state, top: Array(board.prefix(rows)),
                              people: competitors.map(\.username), board: board)
    }
}
