import CoreGraphics
import Testing
@testable import CommitStandingsiOS

/// Keeping a centered column of controls out of a book-style fold: the column moves into one side
/// of the fold instead of straddling it. Frames are leading-based, as `reservedRegions` reports them.
struct FoldAvoidanceTests {
    private let width: CGFloat = 951
    private let height: CGFloat = 669

    @Test func noFoldLeavesTheColumnAlone() {
        #expect(FoldAvoidance.insets(width: width, divisions: []) == .init(leading: 0, trailing: 0))
    }

    @Test func aCenteredFoldSendsTheColumnToTheTrailingSide() {
        // Book pose: equal halves. Trailing is where things keep appearing as the device closes.
        let fold = CGRect(x: 455, y: 0, width: 41, height: height)
        #expect(FoldAvoidance.insets(width: width, divisions: [fold]) == .init(leading: 496, trailing: 0))
    }

    @Test func anOffCenterFoldSendsTheColumnToTheWiderSide() {
        let fold = CGRect(x: 600, y: 0, width: 40, height: height)
        #expect(FoldAvoidance.insets(width: width, divisions: [fold]) == .init(leading: 0, trailing: 351))
    }

    @Test func aFoldAcrossTheWidthIsLeftToScrolling() {
        // Tabletop in portrait: the fold runs across. Scrolling content may pass under it.
        let fold = CGRect(x: 0, y: 460, width: 669, height: 40)
        #expect(FoldAvoidance.insets(width: 669, divisions: [fold]) == .init(leading: 0, trailing: 0))
    }

    @Test func aFoldOutsideTheViewIsIgnored() {
        let fold = CGRect(x: 1_200, y: 0, width: 40, height: height)
        #expect(FoldAvoidance.insets(width: width, divisions: [fold]) == .init(leading: 0, trailing: 0))
    }
}
