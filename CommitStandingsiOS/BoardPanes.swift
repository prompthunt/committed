import SwiftUI

/// Where the Board's summary goes. The leaderboard is the arrangement's primary pane and always
/// shows; the summary is the secondary pane when the arrangement gives it room, and otherwise
/// the leaderboard's first section, so nothing is lost between poses.
///
/// The arrangement doesn't report whether it split: `splitArrangementAxis` reads nil in both
/// panes, and a hidden secondary pane still reports a size (iOS 27.1). So the Board compares
/// the leaderboard pane with the whole arrangement: filling it means it's alone.
struct SummaryPlacement: Equatable {
    private var arrangement: CGSize?
    private var leaderboard: CGSize?

    var isInLeaderboard: Bool {
        guard let arrangement, let leaderboard else { return true }
        // Pane frames can land on fractional points, so allow a point of slack.
        return leaderboard.width >= arrangement.width - 1 && leaderboard.height >= arrangement.height - 1
    }

    mutating func arrangementResized(to size: CGSize) { arrangement = size }
    mutating func leaderboardResized(to size: CGSize) { leaderboard = size }
}

/// Remembers which leaderboard rows are on screen, so when opening or closing the device
/// moves the summary in or out of the list (or reflows it), the list can put back the row
/// you were looking at.
struct LeaderboardScrollAnchor<ID: Hashable> {
    private var visible: Set<ID> = []

    mutating func rowAppeared(_ id: ID) { visible.insert(id) }
    mutating func rowDisappeared(_ id: ID) { visible.remove(id) }

    /// The topmost visible row, in board order. Nil when the first row is visible (the list
    /// is at its top, where the summary header belongs) or nothing is.
    func rowToRestore(in order: [ID]) -> ID? {
        guard let top = order.first(where: visible.contains), top != order.first else { return nil }
        return top
    }
}
