import Testing
import SwiftUI
@testable import CommitStandingsiOS

/// The Board split on iPhone Duo: where the summary goes, and keeping your place in the
/// leaderboard when opening or closing the device changes the layout.
struct BoardPanesTests {

    // MARK: Where the summary goes
    // The arrangement doesn't say whether it split: `splitArrangementAxis` reads nil in both
    // panes, and a hidden secondary pane still reports a size (iOS 27.1). So the Board compares
    // the leaderboard pane with the whole arrangement.

    private let closed = CGSize(width: 393, height: 600)

    @Test func summaryIsTheLeaderboardsHeaderBeforeAnythingIsMeasured() {
        #expect(SummaryPlacement().isInLeaderboard)
    }

    @Test func leaderboardFillingTheArrangementCarriesTheSummary() {
        var placement = SummaryPlacement()
        placement.arrangementResized(to: closed)
        placement.leaderboardResized(to: closed)

        #expect(placement.isInLeaderboard)
    }

    @Test func leaderboardSharingTheArrangementLeavesTheSummaryToItsOwnPane() {
        // Open: side by side. Tabletop: top and bottom.
        var placement = SummaryPlacement()
        placement.arrangementResized(to: CGSize(width: 900, height: 600))
        placement.leaderboardResized(to: CGSize(width: 450, height: 600))
        #expect(!placement.isInLeaderboard)

        placement.arrangementResized(to: CGSize(width: 650, height: 900))
        placement.leaderboardResized(to: CGSize(width: 650, height: 440))
        #expect(!placement.isInLeaderboard)
    }

    @Test func closingAgainPutsTheSummaryBackInTheLeaderboard() {
        var placement = SummaryPlacement()
        placement.arrangementResized(to: CGSize(width: 900, height: 600))
        placement.leaderboardResized(to: CGSize(width: 450, height: 600))
        placement.arrangementResized(to: closed)
        placement.leaderboardResized(to: closed)

        #expect(placement.isInLeaderboard)
    }

    @Test func subPointRoundingStillCountsAsFilling() {
        var placement = SummaryPlacement()
        placement.arrangementResized(to: CGSize(width: 393, height: 600))
        placement.leaderboardResized(to: CGSize(width: 392.67, height: 600))

        #expect(placement.isInLeaderboard)
    }

    // MARK: Keeping your place

    private let order = ["a", "b", "c", "d", "e", "f"]

    @Test func scrolledDownTheTopmostVisibleRowIsTheOneToKeepInPlace() {
        var anchor = LeaderboardScrollAnchor<String>()
        for id in ["e", "c", "d"] { anchor.rowAppeared(id) }

        #expect(anchor.rowToRestore(in: order) == "c")
    }

    @Test func rowsThatScrolledAwayNoLongerCount() {
        var anchor = LeaderboardScrollAnchor<String>()
        for id in ["b", "c", "d"] { anchor.rowAppeared(id) }
        anchor.rowAppeared("e")
        anchor.rowDisappeared("b")
        anchor.rowDisappeared("c")

        #expect(anchor.rowToRestore(in: order) == "d")
    }

    @Test func atTheTopOfTheListThereIsNothingToRestore() {
        // Showing the first row means the list is at (or next to) its top, where the summary
        // header belongs; jumping to the first row would hide that header.
        var anchor = LeaderboardScrollAnchor<String>()
        for id in ["a", "b", "c"] { anchor.rowAppeared(id) }

        #expect(anchor.rowToRestore(in: order) == nil)
    }

    @Test func nothingVisibleMeansNothingToRestore() {
        // At accessibility sizes the summary alone can fill the screen.
        #expect(LeaderboardScrollAnchor<String>().rowToRestore(in: order) == nil)
    }
}
