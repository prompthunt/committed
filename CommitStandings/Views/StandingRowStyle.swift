import SwiftUI

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
    var avatarSize: CGFloat = 26
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

    /// The contribution square right of the count.
    var squares: Squares = .symbol

    enum Squares {
        /// The Mac's `square.grid.2x2.fill`, mint to green relative to the leader.
        case symbol
        /// A single rounded square shaded with these colors: index 0 is an empty day, the last is
        /// the leader's quartile (GitHub-style levels).
        case ramp([Color], size: CGFloat)
    }

    /// The Mac popover's row.
    static let standard = StandingRowStyle()
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
