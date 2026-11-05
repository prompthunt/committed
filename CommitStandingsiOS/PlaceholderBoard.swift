import Foundation

/// The rows the iPhone shell shows before Connect GitHub exists on iOS (#41): the saved board
/// when this device has one, otherwise a fixed sample. Ordering always comes from
/// `Ranking.order`, so the shell ranks exactly like the Mac board.
struct PlaceholderBoard {
    struct Row: Identifiable {
        let rank: Int
        let competitor: Competitor
        let standing: Standing?
        var id: UUID { competitor.id }
    }

    let window: ContributionWindow
    let rows: [Row]
    /// True when no saved people exist and the rows are the built-in sample.
    let isSample: Bool

    /// The leader's count, used to shade each row's contribution square.
    var maxContributions: Int {
        rows.compactMap { $0.standing?.contributions }.max() ?? 0
    }

    @MainActor
    static func make(store: StandingsStore, window: ContributionWindow) -> PlaceholderBoard {
        let saved = store.visibleCompetitors
        if saved.isEmpty {
            return board(competitors: Sample.competitors, standings: Sample.standings(for: window), window: window, isSample: true)
        }
        return board(competitors: saved, standings: store.standings(for: window), window: window, isSample: false)
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

    /// A small, fixed board so a fresh install renders real `StandingRow`s.
    private enum Sample {
        static let counts: [(username: String, contributions: Int)] = [
            ("octocat", 9), ("hubot", 6), ("mona", 14), ("defunkt", 2),
        ]

        static let competitors: [Competitor] = counts.map {
            Competitor(username: $0.username, isSelf: $0.username == "octocat")
        }

        static func standings(for window: ContributionWindow) -> [String: Standing] {
            Dictionary(uniqueKeysWithValues: counts.map {
                ($0.username, Standing(
                    username: $0.username,
                    contributions: $0.contributions,
                    window: window,
                    lastUpdated: Date(timeIntervalSince1970: 1_800_000_000),
                    state: .loaded
                ))
            })
        }
    }
}
