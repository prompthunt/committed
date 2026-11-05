import CoreGraphics
import Testing
@testable import CommitStandingsiOS

/// Where your summary goes on the Board. The arrangement decides whether there's room for the
/// summary pane; the leaderboard only reacts to where the panes actually are, so the summary is
/// never lost between poses.
struct BoardArrangementTests {
    private let open = CGRect(x: 0, y: 0, width: 951, height: 600)
    private let leaderboardHalf = CGRect(x: 0, y: 0, width: 475, height: 600)
    private let summaryHalf = CGRect(x: 476, y: 0, width: 475, height: 600)
    private let closed = CGRect(x: 0, y: 0, width: 382, height: 562)

    private func placement(_ arrangement: CGRect?, _ leaderboard: CGRect?, _ summary: CGRect?)
        -> BoardArrangement.SummaryPlacement {
        BoardArrangement.summaryPlacement(arrangement: arrangement, leaderboard: leaderboard, summary: summary)
    }

    @Test func leaderboardCarriesTheSummaryBeforeThePanesHaveReported() {
        #expect(placement(nil, nil, nil) == .leaderboardHeader)
        #expect(placement(open, leaderboardHalf, nil) == .leaderboardHeader)
        #expect(placement(nil, leaderboardHalf, summaryHalf) == .leaderboardHeader)
    }

    @Test func leaderboardCarriesTheSummaryWhenThePaneIsHiddenUnderIt() {
        // Measured on the closed iPhone Duo: the arrangement keeps the hidden secondary pane laid
        // out at the primary pane's frame.
        #expect(placement(closed, closed, closed) == .leaderboardHeader)
    }

    @Test func leaderboardTakesTheSummaryBackAfterClosing() {
        // Measured after open → close: the hidden pane stops reporting, so its last frame is the
        // side-by-side one from the open display.
        #expect(placement(closed, closed, summaryHalf) == .leaderboardHeader)
    }

    @Test func leaderboardCarriesTheSummaryWhenThePaneIsCollapsed() {
        let collapsed = CGRect(x: 951, y: 0, width: 0, height: 600)
        #expect(placement(open, open, collapsed) == .leaderboardHeader)
    }

    @Test func summaryUsesItsOwnPaneWhenThePanesSitSideBySide() {
        #expect(placement(open, leaderboardHalf, summaryHalf) == .secondaryPane)
    }
}
