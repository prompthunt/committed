import CoreGraphics

/// Where your summary goes on the Board. `BoardView` arranges two panes, the leaderboard
/// (primary) and your summary (secondary), and the system decides whether there's room for both.
/// Both panes report their frames and the leaderboard reacts, so the summary is always somewhere:
/// in its own pane when the panes sit side by side, otherwise at the top of the leaderboard.
///
/// Frames are the signal because nothing simpler works in the iOS 27.1 SDK. `splitArrangementAxis`
/// still reads `.vertical` on a pane when `.axes(.horizontal)` leaves only the primary showing, and
/// nil inside a `List`. The hidden secondary pane isn't removed either: it stays laid out, full
/// size, at the primary pane's frame, and gets `onAppear`. After the panes go from side by side
/// back to one, the hidden pane stops reporting, so its last frame is stale; the arrangement's own
/// width tells the two cases apart.
enum BoardArrangement {
    enum SummaryPlacement: Equatable {
        case leaderboardHeader
        case secondaryPane
    }

    /// Frames are in the arrangement's coordinate space; nil until reported. The summary has its
    /// own pane only when both panes are on screen next to each other, which means together they
    /// fit in the arrangement's width.
    static func summaryPlacement(arrangement: CGRect?, leaderboard: CGRect?, summary: CGRect?) -> SummaryPlacement {
        guard let arrangement, let leaderboard, let summary,
              !leaderboard.isEmpty, !summary.isEmpty,
              !leaderboard.intersects(summary),
              leaderboard.width + summary.width <= arrangement.width + 1
        else { return .leaderboardHeader }
        return .secondaryPane
    }

    enum PersonPlacement: Equatable {
        case sheet
        case secondaryPane
    }

    /// Where a tapped Competitor's person view goes: in the second pane, in place of your summary,
    /// whenever the summary has a pane of its own (iPhone Duo open), otherwise a sheet over the
    /// Board. The same frames decide both, so the person view never lands in a hidden pane.
    static func personPlacement(summary: SummaryPlacement) -> PersonPlacement {
        summary == .secondaryPane ? .secondaryPane : .sheet
    }
}
