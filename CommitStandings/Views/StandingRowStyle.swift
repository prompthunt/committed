import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// How the shared `StandingRow` is drawn. The Mac popover and the iPhone board use the same row
/// (one row, never forked); the iPhone restyles it by setting `\.standingRowStyle`. The default,
/// `.standard`, is the Mac's look exactly, so the Mac never sets anything.
///
/// Values only, no closures, so it's a stable environment value. A `nil` color means "what the
/// Mac row has always used" (`.tint` for the accent, `.secondary` for quiet text).
struct StandingRowStyle {
    /// The rank column ("#3").
    var rankFont: Font = .caption.monospacedDigit()
    var rankColor: Color? = nil
    /// Base width of the rank column; grows with Dynamic Type (see `StandingRow.rankWidth`).
    var rankWidthScale: CGFloat = 1
    var nameFont: Font = .callout
    var selfNameFont: Font = .callout.weight(.semibold)
    var countFont: Font = .callout.monospacedDigit()
    var selfCountFont: Font = .callout.monospacedDigit().weight(.semibold)
    /// Your count's color. nil = the row's text color (the Mac).
    var selfCountColor: Color? = nil
    var avatarSize: CGFloat = 26
    /// The count column's minimum width, so counts line up down the list. A small widget, too
    /// narrow to spare it, sets 0.
    var countMinWidth: CGFloat = 40
    /// Keep the count whole on one line, letting the name truncate first. A narrow row (a small
    /// widget) sets it; the board's rows have the room.
    var keepsCountWhole: Bool = false
    /// The "you" badge beside your name. A small widget drops it; your row's highlight still
    /// marks you.
    var showsSelfBadge: Bool = true
    var spacing: CGFloat = 10
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 7

    /// The "you" badge and your row's highlight. nil = `.tint`.
    var accent: Color? = nil
    var badgeFont: Font = .caption2
    /// The badge's label color. nil = the accent. Set it when the badge is a solid fill.
    var badgeForeground: Color? = nil
    var badgeFillOpacity: Double = 0.18
    var selfFillOpacity: Double = 0.12
    var selfStrokeOpacity: Double = 0.30
    var cornerRadius: CGFloat = 8

    var movementUpColor: Color = .green
    var movementDownColor: Color? = nil
    var movementFont: Font = .system(size: 9, weight: .semibold)
    /// The streak (mark and "12") beside the count. nil color = `.secondary`.
    var streakFont: Font = .caption.monospacedDigit()
    var streakColor: Color? = nil
    /// The streak mark's base size and the text style it scales with, matching `streakFont`.
    var streakMarkSize: CGFloat = 11
    var streakTextStyle: Font.TextStyle = .caption
    /// The mark's own color. nil = the number's (`streakColor`).
    var streakMarkColor: Color? = nil

    /// The contribution square right of the count.
    var squares: Squares = .symbol

    /// A trolling row (see `TrollCheck`): its count turns this red and the troll face takes the
    /// square's place, drawn at this size and centered on the square's slot so counts stay aligned.
    var trollColor: Color = .trollRed
    var trollSize = CGSize(width: 19, height: 16)

    enum Squares {
        /// The Mac's `square.grid.2x2.fill`, mint to green relative to the leader.
        case symbol
        /// The same glyph, tinted by `SquareRamp` level with these colors: index 0 is no
        /// contributions, the last is the leader's quartile (GitHub-style levels).
        case shadedSymbol([Color])
        /// No square: a row too narrow to spare it (a small widget).
        case hidden
    }

    /// The Mac popover's row.
    static let standard = StandingRowStyle()
}

extension StandingRowStyle.Squares {
    /// False for a row too narrow for the square, which also leaves out the troll face.
    var isShown: Bool {
        if case .hidden = self { return false }
        return true
    }
}

extension EnvironmentValues {
    @Entry var standingRowStyle = StandingRowStyle.standard
}

/// Which shade of a contribution-square ramp a count gets: 0 for no contributions (or no leader
/// yet), then quartiles of the leader's count, as GitHub's graph does.
enum SquareRamp {
    static let levels = 5

    static func level(value: Int, max: Int) -> Int {
        guard value > 0, max > 0 else { return 0 }
        let fraction = Double(value) / Double(max)
        switch fraction {
        case ...0.25: return 1
        case ...0.5: return 2
        case ...0.75: return 3
        default: return 4
        }
    }
}

extension Color {
    /// A trolling count's red: bright on dark, deeper on light so it stays readable (5:1 or better).
    static let trollRed: Color = {
        let bright = (red: 1.0, green: 0.31, blue: 0.25)
        let deep = (red: 0.784, green: 0.2, blue: 0.122)
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? bright : deep
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? bright : deep
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #endif
    }()
}
