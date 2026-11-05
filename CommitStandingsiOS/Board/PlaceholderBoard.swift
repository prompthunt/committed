import Foundation

/// The rows the iPhone shell shows before Connect GitHub and live refresh exist: saved standings
/// when this device has any, otherwise a fixed sample so the board is never blank. Ordering comes
/// from `Ranking.order`, the same function the Mac board uses.
struct PlaceholderBoard {
    struct Row: Identifiable {
        let rank: Int
        let competitor: Competitor
        let standing: Standing?
        var id: UUID { competitor.id }
    }

    let window: ContributionWindow
    let rows: [Row]
    /// True when the rows are the built-in sample, not this device's saved standings.
    let isSample: Bool

    /// The leader's count, used to shade each row's contribution square.
    var maxContributions: Int {
        rows.compactMap { $0.standing?.contributions }.max() ?? 0
    }

    static func make(
        competitors: [Competitor],
        standings: [String: Standing],
        window: ContributionWindow
    ) -> PlaceholderBoard {
        guard !competitors.isEmpty else {
            return board(competitors: Sample.competitors, standings: Sample.standings(for: window),
                         window: window, isSample: true)
        }
        return board(competitors: competitors, standings: standings, window: window, isSample: false)
    }

    private static func board(
        competitors: [Competitor],
        standings: [String: Standing],
        window: ContributionWindow,
        isSample: Bool
    ) -> PlaceholderBoard {
        let rows = Ranking.order(competitors: competitors, standings: standings, window: window).map {
            Row(rank: $0.rank, competitor: $0.competitor, standing: standings[$0.competitor.username])
        }
        return PlaceholderBoard(window: window, rows: rows, isSample: isSample)
    }

    private enum Sample {
        // Spaces and periods make these impossible GitHub logins, so the avatar request can never
        // resolve to a real person and each row falls back to colored initials.
        static let counts: [(username: String, isSelf: Bool, contributions: Int)] = [
            ("Your name", true, 7),
            ("Maya R.", false, 12),
            ("Devon K.", false, 4),
            ("Priya S.", false, 9),
            ("Sam L.", false, 0),
        ]

        static let competitors = counts.map { Competitor(username: $0.username, isSelf: $0.isSelf) }

        static func standings(for window: ContributionWindow) -> [String: Standing] {
            Dictionary(uniqueKeysWithValues: counts.map {
                ($0.username, Standing(username: $0.username, contributions: $0.contributions,
                                       window: window, lastUpdated: .now, state: .loaded))
            })
        }
    }
}
