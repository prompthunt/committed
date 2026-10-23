import Foundation

/// The single source of truth for board ordering, shared by the views (display) and the
/// RefreshCoordinator (rank-delta tracking) so a rank computed in one place always matches the
/// other. Rank by contributions descending; a competitor with no standing for the window (or whose
/// cached standing is for a different window) sorts last; ties fall back to the original competitor
/// order for stability. Ranks start at 1.
enum Ranking {
    struct Entry: Identifiable, Equatable {
        let rank: Int
        let competitor: Competitor
        var id: UUID { competitor.id }
    }

    static func order(
        competitors: [Competitor],
        standings: [String: Standing],
        window: ContributionWindow
    ) -> [Entry] {
        let indexed = competitors.enumerated().map { (idx, competitor) -> (Int, Competitor, Int) in
            let standing = standings[competitor.username]
            let contributions = standing?.window == window ? (standing?.contributions ?? -1) : -1
            return (idx, competitor, contributions)
        }
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.2 == rhs.2 { return lhs.0 < rhs.0 }
            return lhs.2 > rhs.2
        }
        return sorted.enumerated().map { (rank, tuple) in
            Entry(rank: rank + 1, competitor: tuple.1)
        }
    }
}
