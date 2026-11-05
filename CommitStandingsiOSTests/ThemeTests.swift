import SwiftUI
import Testing
import UIKit
@testable import CommitStandingsiOS

/// The iPhone theme (#51): the marketing site's ink-and-lime palette and Inter Tight, dark only.
struct ThemeTests {
    // MARK: Type

    /// `Font.custom` silently falls back to SF when a face isn't registered, so check the bundle.
    @Test(arguments: [CommittedType.regularFace, CommittedType.displayFace])
    func interTightIsBundledAndRegistered(face: String) {
        #expect(UIFont(name: face, size: 17) != nil)
    }

    // MARK: Contrast (WCAG AA: 4.5:1 for text, 3:1 for large text and UI marks)

    @Test(arguments: [
        ("white on ink", Palette.white, Palette.ink),
        ("soft on ink", Palette.soft, Palette.ink),
        ("muted on ink", Palette.muted, Palette.ink),
        ("muted on tile", Palette.muted, Palette.tile),
        ("muted on raised", Palette.muted, Palette.raised),
        ("lime on ink", Palette.lime, Palette.ink),
        ("lime on tile", Palette.lime, Palette.tile),
        ("on-lime on lime", Palette.onLime, Palette.lime),
        ("ink on lime", Palette.ink, Palette.lime),
        ("warning on ink", Palette.warning, Palette.ink),
        ("white on raised", Palette.white, Palette.raised),
    ])
    func textPairsMeetAA(name: String, foreground: Palette.RGB, background: Palette.RGB) {
        #expect(Palette.contrast(foreground, background) >= 4.5, "\(name)")
    }

    /// The brightest contribution square has to read as a mark against ink.
    @Test func topSquareReadsAgainstInk() {
        #expect(Palette.contrast(Palette.squares[3], Palette.ink) >= 3)
    }

    // MARK: Contribution squares

    @Test func emptyAndMissingCountsUseTheEmptySquare() {
        #expect(SquareRamp.level(value: 0, max: 12) == 0)
        #expect(SquareRamp.level(value: 5, max: 0) == 0)
    }

    @Test func countsShadeByQuartileOfTheLeader() {
        #expect(SquareRamp.level(value: 1, max: 12) == 1)
        #expect(SquareRamp.level(value: 3, max: 12) == 1)
        #expect(SquareRamp.level(value: 4, max: 12) == 2)
        #expect(SquareRamp.level(value: 7, max: 12) == 3)
        #expect(SquareRamp.level(value: 10, max: 12) == 4)
        #expect(SquareRamp.level(value: 12, max: 12) == 4)
        #expect(SquareRamp.level(value: 40, max: 12) == 4)
    }
}
