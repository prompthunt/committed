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

    /// Stale Live rank swaps lime for the deeper lime instead of dimming it.
    @Test func deepLimeReadsOnInk() {
        #expect(Palette.contrast(Palette.limeDeep, Palette.ink) >= 4.5)
    }

    /// Text over a square field, against the brightest pixel that field can draw: the glow at its
    /// center with the top allowed square on it at full opacity. Muted text never sits on a field.
    @Test(arguments: [
        ("hero", FieldTone.hero, Palette.tile),
        ("Lock Screen", FieldTone.lockScreen, Palette.ink),
        ("Connect GitHub", FieldTone.connect, Palette.ink),
        ("Live rank disclosure", FieldTone.disclosure, Palette.ink),
    ])
    func textOverTheFieldMeetsAA(name: String, tone: FieldTone, background: Palette.RGB) {
        let brightest = tone.brightest(on: background)
        for (token, color) in [("white", Palette.white), ("soft", Palette.soft), ("lime", Palette.lime)] {
            #expect(Palette.contrast(color, brightest) >= 4.5, "\(token) over the \(name) field")
        }
    }

    /// The cap is what keeps text legible; without it the hero's top square alone fails soft text.
    @Test func theHeroFieldNeedsItsOpacityCap() {
        var uncapped = FieldTone.hero
        uncapped.maxOpacity = 1
        #expect(Palette.contrast(Palette.soft, uncapped.brightest(on: Palette.tile)) < 4.5)
    }

    /// The brightest contribution square has to read as a mark against ink.
    @Test func topSquareReadsAgainstInk() {
        #expect(Palette.contrast(Palette.squares[3], Palette.ink) >= 3)
    }

    /// The rows' 2×2 squares glyph (the Mac's `square.grid.2x2.fill`) is a UI mark: every shade has
    /// to read at 3:1 wherever a row sits: the board (ink, a tile card, your lime-tinted row),
    /// the black Dynamic Island, and the Lock Screen's ink.
    @Test(arguments: [
        ("ink", Palette.ink),
        ("tile", Palette.tile),
        ("raised", Palette.raised),
        ("the Dynamic Island", Palette.RGB(0x000000)),
        ("your row", Palette.tile.blended(with: Palette.lime, 0.07)),
    ])
    func rowGlyphShadesReadAsMarks(name: String, background: Palette.RGB) {
        #expect(Palette.rowGlyphs.count == SquareRamp.levels)
        for (level, shade) in Palette.rowGlyphs.enumerated() {
            #expect(Palette.contrast(shade, background) >= 3, "level \(level) on \(name)")
        }
    }

    /// Busier is brighter, as on the site's graph, from the first contribution up to the leader's
    /// quartile. Level 0 (no contributions) is gray, GitHub's empty square.
    @Test func rowGlyphShadesBrightenWithTheCount() {
        let greens = Palette.rowGlyphs.dropFirst().map(\.luminance)
        #expect(zip(greens, greens.dropFirst()).allSatisfy { $0 < $1 })
        #expect(Palette.rowGlyphs.first?.luminance == Palette.muted.luminance)
        // Full lime stays the hero's and the burst's.
        #expect(Palette.rowGlyphs.last?.luminance == Palette.limeDeep.luminance)
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
