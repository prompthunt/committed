import Foundation

/// What the Board tab shows for the selected Window, derived from the shared store. Ordering
/// comes only from `Ranking.order`, so the iPhone ranks exactly like the Mac.
@MainActor
struct Board {
    struct Row: Identifiable {
        let rank: Int
        let competitor: Competitor
        let standing: Standing?
        /// Today's movement (+ up, − down); only on the Today board.
        let rankDelta: Int?
        var id: UUID { competitor.id }
    }

    /// You, for the summary at the top of the board.
    struct Summary: Equatable {
        let username: String
        let window: ContributionWindow
        /// Your place; nil until your numbers load, or when nobody else is visible.
        let rank: Int?
        /// Everyone visible on the board, including you.
        let competitorCount: Int
        /// Your Contributions for the Window; nil (a placeholder, never zero) until loaded.
        let contributions: Int?
        /// Places moved since the start of today (+ up, − down); nil when you held your place,
        /// have no rank, or the board isn't Today.
        let movementToday: Int?
        /// Saved numbers are showing while fresh ones load.
        let isRefreshing: Bool
    }

    let window: ContributionWindow
    let rows: [Row]
    /// nil until people have synced and you're on the board.
    let summary: Summary?

    /// The leader's count, to shade each row's contribution square.
    var maxContributions: Int {
        rows.compactMap { row in row.standing.flatMap { $0.lastUpdated == .distantPast ? nil : $0.contributions } }
            .max() ?? 0
    }

    init(store: StandingsStore, refresh: RefreshCoordinator) {
        let window = store.selectedWindow
        let standings = store.standings(for: window)
        self.window = window
        let rows = Ranking.order(competitors: store.visibleCompetitors, standings: standings, window: window).map {
            let username = $0.competitor.username
            return Row(
                rank: $0.rank,
                competitor: $0.competitor,
                standing: standings[username],
                rankDelta: window == .daily ? refresh.rankDelta(for: username) : nil
            )
        }
        self.rows = rows
        // Your rank, count, and movement follow Live rank's rules (one derivation, one
        // placeholder check), so the summary and Live rank never disagree.
        summary = rows.first(where: \.competitor.isSelf).map { me in
            let state = LiveRankState.derive(
                competitors: store.visibleCompetitors,
                standings: standings,
                window: window,
                rankDeltas: me.rankDelta.map { [me.competitor.username: $0] } ?? [:],
                now: .now
            )
            return Summary(
                username: me.competitor.username,
                window: window,
                rank: state.rank,
                competitorCount: state.competitorCount,
                contributions: state.contributions,
                movementToday: state.movementToday == 0 ? nil : state.movementToday,
                isRefreshing: state.contributions != nil && me.standing?.state == .loading
            )
        }
    }
}
