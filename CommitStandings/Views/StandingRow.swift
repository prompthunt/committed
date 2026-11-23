import SwiftUI

struct StandingRow: View {
    let rank: Int
    let competitor: Competitor
    let standing: Standing?
    let window: ContributionWindow
    /// The largest contribution count among the rows being shown, so the green square can be
    /// shaded relative to the leader (GitHub-style). 0 ⇒ no shading reference yet.
    var maxContributions: Int = 0
    /// Change in this row's placement since the start of the day (+ up, − down). nil/0 ⇒ no marker.
    var rankDelta: Int? = nil
    /// Days in a row with a contribution (`ContributionHistory.currentStreak`). Shown as the streak
    /// mark and "12" from 2 days, and only once this row's count has loaded. nil ⇒ no history yet.
    var streak: Int? = nil
    /// A line under the name: the gap on the iPhone's Your rivals ("3 to pass", "Level"). nil ⇒ the
    /// row stays one line, as everywhere else.
    var caption: String? = nil
    /// Shown in place of the streak: a rivalry record ("7–5") on Your rivals. nil ⇒ the streak.
    var record: String? = nil
    /// How VoiceOver reads `record`: "You've won 7 of the last 12 weeks against ezra-q". nil ⇒
    /// "record 7–5".
    var recordSpoken: String? = nil
    /// Grows with Dynamic Type on iPhone so "#12" never truncates; stays 24pt on the Mac.
    @ScaledMetric(relativeTo: .caption) private var rankWidth: CGFloat = 24
    /// iPhone at accessibility text sizes wraps long usernames instead of truncating them.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The Mac's look by default; the iPhone sets its own (see `StandingRowStyle`).
    @Environment(\.standingRowStyle) private var style

    var body: some View {
        layout
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .background(selfHighlight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .help(trollDescription.map { "Problem? \($0)." } ?? "")
    }

    /// Your row never loses your name. When it doesn't fit whole, the "you" badge goes first (the
    /// row's highlight already says it's you), then your streak (your summary still has it), and
    /// last the name wraps onto two lines, or shrinks a little where a row has no room for a second
    /// line. Rivals' rows keep everything and truncate the name.
    @ViewBuilder
    private var layout: some View {
        if competitor.isSelf {
            ViewThatFits(in: .horizontal) {
                content(badge: style.showsSelfBadge, streak: true, wraps: false)
                content(badge: false, streak: true, wraps: false)
                content(badge: false, streak: false, wraps: false)
                content(badge: false, streak: false, wraps: true)
            }
        } else {
            content(badge: false, streak: true, wraps: false)
        }
    }

    private func content(badge: Bool, streak showsStreak: Bool, wraps: Bool) -> some View {
        HStack(spacing: style.spacing) {
            Text("#\(rank)")
                .font(style.rankFont)
                .foregroundStyle(style.rankColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: rankWidth * style.rankWidthScale, alignment: .trailing)
            AvatarView(username: competitor.username, size: style.avatarSize)
            nameStack(badge: badge, wraps: wraps)
            Spacer(minLength: 6)
            // Numbers are never cut or wrapped ("6,28" over "7"): this group lays out first, so the
            // name truncates before the count gives up any width. Only where even the count can't
            // fit (the largest text sizes) does it shrink a little, still on one line.
            HStack(spacing: 4) {
                rankDeltaIndicator
                if let record {
                    recordLabel(record)
                } else if showsStreak {
                    streakLabel
                }
                contributionsLabel
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: style.countMinWidth, alignment: .trailing)
            }
            .layoutPriority(1)
            contributionSquare
        }
    }

    /// The name (with the "you" badge), and the caption under it when the row has one.
    @ViewBuilder
    private func nameStack(badge: Bool, wraps: Bool) -> some View {
        if let caption {
            VStack(alignment: .leading, spacing: 1) {
                nameLine(badge: badge, wraps: wraps)
                Text(caption)
                    .font(style.captionFont)
                    .foregroundStyle(style.captionColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        } else {
            nameLine(badge: badge, wraps: wraps)
        }
    }

    private func nameLine(badge: Bool, wraps: Bool) -> some View {
        HStack(spacing: 4) {
            Text(competitor.username)
                .font(competitor.isSelf ? style.selfNameFont : style.nameFont)
                .lineLimit(wraps || dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                // Where a second line has no room (a small widget's four rows), shrink a little.
                .minimumScaleFactor(wraps ? 0.75 : 1)
                .truncationMode(.middle)
            if badge {
                Text("you")
                    .font(style.badgeFont)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(accent.opacity(style.badgeFillOpacity), in: .capsule)
                    .foregroundStyle(style.badgeForeground.map(AnyShapeStyle.init) ?? accent)
            }
        }
    }

    /// The record in the streak's place, in the streak's type.
    private func recordLabel(_ record: String) -> some View {
        Text(record)
            .font(style.streakFont)
            .monospacedDigit()
            .foregroundStyle(style.streakColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .lineLimit(1)
            .fixedSize()
            // The row's own label reads the record.
            .accessibilityHidden(true)
    }

    /// The window's observed burst, once the row has data.
    private var burst: Burst? {
        hasData ? standing?.burst : nil
    }

    /// Describe the observed change without assuming when the contributions happened.
    private var trollDescription: String? {
        guard let burst else { return nil }
        let increase = "Count rose by \(burst.count.formatted()) between refreshes within six minutes"
        guard let multiple = burst.multiple else { return increase }
        return "\(increase), about \(multiple) times their usual big day"
    }

    /// Your own row gets the same treatment as the hero card: a soft tint fill with a thin tint
    /// hairline border, so "you" reads consistently in the card and the list.
    @ViewBuilder
    private var selfHighlight: some View {
        if competitor.isSelf {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(accent.opacity(style.selfFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .stroke(accent.opacity(style.selfStrokeOpacity), lineWidth: 1)
                )
        }
    }

    /// The badge and highlight color: the style's accent, or the tint (the Mac).
    private var accent: AnyShapeStyle {
        style.accent.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint)
    }

    /// A small, quiet chevron showing how this row moved since the start of the day: a single
    /// chevron for a one-spot move, a double chevron for two or more. Up is green, down is muted so
    /// it never feels like a scolding. Nothing renders when the position held.
    @ViewBuilder
    private var rankDeltaIndicator: some View {
        if let delta = rankDelta, delta != 0 {
            Image(systemName: deltaSymbol(delta))
                .font(style.movementFont)
                .foregroundStyle(delta > 0 ? style.movementUpColor : (style.movementDownColor ?? Color.secondary))
                .accessibilityLabel(delta > 0 ? "up \(delta)" : "down \(-delta)")
        }
    }

    private func deltaSymbol(_ delta: Int) -> String {
        switch delta {
        case 2...: return "chevron.up.2"
        case 1: return "chevron.up"
        case -1: return "chevron.down"
        default: return "chevron.down.2"
        }
    }

    /// A small green square (à la the GitHub contribution graph) right of the number — lighter for
    /// low counts, richer/darker green for high. Hidden when there's no data yet.
    @ViewBuilder
    private var contributionSquare: some View {
        if burst != nil, style.squares.isShown {
            Image("Troll")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
                .frame(width: style.trollSize.width, height: style.trollSize.height)
                .frame(width: 16)
                .accessibilityHidden(true)
        } else {
            squareGlyph
        }
    }

    @ViewBuilder
    private var squareGlyph: some View {
        switch style.squares {
        case .symbol:
            if hasData, let standing {
                Image(systemName: "square.grid.2x2.fill")
                    .imageScale(.small)
                    .foregroundStyle(ContributionShade.color(value: standing.contributions, max: maxContributions))
                    .frame(width: 16)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 16)
            }
        case .shadedGrid(let colors):
            if hasData, let standing, !colors.isEmpty {
                let level = min(SquareRamp.level(value: standing.contributions, max: maxContributions), colors.count - 1)
                ContributionGrid(size: 12, color: colors[level])
                    .frame(width: 16)
            } else {
                Color.clear.frame(width: 16)
            }
        case .hidden:
            EmptyView()
        }
    }

    var accessibilityDescription: String {
        let movement = rankDelta.map { delta in
            delta == 0 ? "" : ", \(delta > 0 ? "up" : "down") \(delta.magnitude) \(delta.magnitude == 1 ? "place" : "places") today"
        } ?? ""
        // A record (Your rivals) is read in the streak's place, as it's drawn there.
        let streakOrRecord: String
        if let record {
            if let recordSpoken {
                let lowered: String = recordSpoken.prefix(1).lowercased() + String(recordSpoken.dropFirst())
                streakOrRecord = ", " + lowered
            } else {
                streakOrRecord = ", record \(record)"
            }
        } else if hasData, let spokenStreak = StreakLabel.spoken(streak) {
            streakOrRecord = ", " + spokenStreak
        } else {
            streakOrRecord = ""
        }
        let trolling = trollDescription.map { ", trolling: \($0)" } ?? ""
        let gap = caption.map { ", " + $0.lowercased() } ?? ""
        return standingDescription + gap + streakOrRecord + movement + trolling
    }

    /// The streak's number beside the mark ("12", "365+"), or nil: under 2 days, or no count
    /// loaded (a failed or first load shows no streak, never "0").
    var streakNumber: String? {
        hasData ? StreakLabel.number(streak) : nil
    }

    @ViewBuilder
    private var streakLabel: some View {
        if streakNumber != nil {
            StreakBadge(streak: streak, markSize: style.streakMarkSize, relativeTo: style.streakTextStyle,
                        markColor: style.streakMarkColor ?? style.streakColor)
                .font(style.streakFont)
                .foregroundStyle(style.streakColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .lineLimit(1)
                .fixedSize()
                // The row's own label reads the streak.
                .accessibilityHidden(true)
        }
    }

    private var standingDescription: String {
        let who = competitor.isSelf ? "you" : competitor.username
        switch standing?.state {
        case .failed(let message) where !hasData:
            return "rank \(rank), \(who), no data: \(message)"
        case .failed(let message):
            return "rank \(rank), \(who), stale, \(contributionsText) contributions for \(window.accessibilityDescription). Refresh failed: \(message)"
        case .loading where !hasData:
            return "rank \(rank), \(who), loading"
        default:
            return "rank \(rank), \(who), \(contributionsText) contributions for \(window.accessibilityDescription)"
        }
    }

    private var hasData: Bool {
        guard let standing else { return false }
        return standing.lastUpdated != .distantPast
    }

    /// A row with cached numbers that's fetching fresh ones: keep the value visible and
    /// pulse it, rather than swapping in a spinner.
    private var isRefreshing: Bool {
        standing?.state == .loading && hasData
    }

    private var contributionsText: String {
        guard let standing, hasData else { return "—" }
        return standing.contributions.formatted()
    }

    @ViewBuilder
    private var contributionsLabel: some View {
        switch standing?.state {
        case .loading where !hasData:
            SkeletonCell()
        case .failed where !hasData:
            Text("—")
                .font(style.countFont)
                .foregroundStyle(.orange)
        default:
            if burst != nil {
                Text(contributionsText)
                    .font(competitor.isSelf ? style.selfCountFont : style.countFont)
                    .foregroundStyle(style.trollColor)
                    .pulsing(isRefreshing)
            } else if competitor.isSelf, let color = style.selfCountColor {
                Text(contributionsText)
                    .font(style.selfCountFont)
                    .foregroundStyle(color)
                    .pulsing(isRefreshing)
            } else {
                Text(contributionsText)
                    .font(competitor.isSelf ? style.selfCountFont : style.countFont)
                    .pulsing(isRefreshing)
            }
        }
    }
}

/// How a streak reads wherever it shows: the streak mark and "12" from 2 days (a mark on every
/// 1-day row would clutter the board), "365+" past GitHub's calendar (about a year, so the app
/// never claims more than it can see), and "12-day streak" to VoiceOver.
enum StreakLabel {
    /// Shortest streak shown.
    static let minimum = 2
    /// Longest streak shown as a number; anything longer reads "365+".
    static let cap = 365

    static func spoken(_ streak: Int?) -> String? {
        guard let streak, streak >= minimum else { return nil }
        return streak > cap ? "\(cap)-plus-day streak" : "\(streak)-day streak"
    }

    /// A person view streak stat read aloud: "12 days", or "365-plus days" past the calendar (shown
    /// as "365+ days", `PersonSummary.streakText`), never "365 plus sign".
    static func spokenDays(_ days: Int) -> String {
        days > cap ? "\(cap)-plus days" : "\(days) \(days == 1 ? "day" : "days")"
    }

    /// "12", "365+", or nil under 2 days.
    static func number(_ streak: Int?) -> String? {
        guard let streak, streak >= minimum else { return nil }
        return streak > cap ? "\(cap)+" : "\(streak)"
    }
}

/// The streak mark: a flame with a contribution square at its heart
/// (`docs/design/committed-streak-glyph.svg`), on the trophy's 16 × 16 grid. One shape in one
/// color, so it tints like text: lime or deep lime on the dark iPhone surfaces, stepping down when
/// stale, and plain secondary gray on the Mac. Fill it with `eoFill` so the square stays open.
struct StreakGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        let origin = CGPoint(x: rect.midX - 8 * scale, y: rect.midY - 8 * scale)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }
        var path = Path()
        path.move(to: p(8, 15.6))
        path.addCurve(to: p(2.3, 10.2), control1: p(4.6, 15.6), control2: p(2.3, 13.2))
        path.addCurve(to: p(4.2, 5.8), control1: p(2.3, 8.4), control2: p(3.1, 6.9))
        path.addCurve(to: p(5.8, 8.4), control1: p(4.4, 7.2), control2: p(5, 8))
        path.addCurve(to: p(9, 0.4), control1: p(5.6, 5.4), control2: p(7, 2.6))
        path.addCurve(to: p(13.7, 10.2), control1: p(11.8, 2.8), control2: p(13.7, 6.2))
        path.addCurve(to: p(8, 15.6), control1: p(13.7, 13.2), control2: p(11.4, 15.6))
        path.closeSubpath()
        path.addRect(CGRect(origin: p(5.9, 9.7), size: CGSize(width: 4.2 * scale, height: 4.2 * scale)))
        return path
    }
}

/// The streak mark alone, sized with the text it sits beside. nil color = the foreground style.
struct StreakMark: View {
    var color: Color? = nil
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body, color: Color? = nil) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.color = color
    }

    var body: some View {
        StreakGlyph()
            .fill(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground), style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            // Sit on the text's baseline the way a glyph would, not centered on the line.
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - $0.height * 0.06 }
            .alignmentGuide(.lastTextBaseline) { $0[.bottom] - $0.height * 0.06 }
            .accessibilityHidden(true)
    }
}

/// A streak as it shows everywhere: the mark, then the number ("12", "365+"), read aloud as
/// "12-day streak". Nothing under 2 days or without a streak. Takes its font and number color
/// from the environment.
struct StreakBadge: View {
    let streak: Int?
    let markSize: CGFloat
    var textStyle: Font.TextStyle = .body
    var markColor: Color? = nil

    init(streak: Int?, markSize: CGFloat, relativeTo textStyle: Font.TextStyle = .body, markColor: Color? = nil) {
        self.streak = streak
        self.markSize = markSize
        self.textStyle = textStyle
        self.markColor = markColor
    }

    var body: some View {
        if let number = StreakLabel.number(streak) {
            HStack(alignment: .firstTextBaseline, spacing: markSize * 0.25) {
                StreakMark(size: markSize, relativeTo: textStyle, color: markColor)
                Text(number)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StreakLabel.spoken(streak) ?? "")
        }
    }
}

/// Four rounded squares drawn as shapes so they render in exported images.
struct ContributionGrid: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        let gap = size * 0.12
        let cell = (size - gap) / 2
        let square = RoundedRectangle(cornerRadius: cell * 0.22)
            .fill(color)
            .frame(width: cell, height: cell)

        VStack(spacing: gap) {
            HStack(spacing: gap) {
                square
                square
            }
            HStack(spacing: gap) {
                square
                square
            }
        }
        .accessibilityHidden(true)
    }
}

/// Maps a contribution count to a green shade relative to the leader — light mint for low,
/// richer/darker green for high — staying visible on the dark background. Mirrors the feel of
/// the GitHub contribution-graph scale.
enum ContributionShade {
    static func color(value: Int, max: Int) -> Color {
        let fraction = max > 0 ? min(1.0, Double(value) / Double(max)) : 0
        // Light mint (#9be9a8) → vivid green (#2ea043). Higher = darker/richer, still legible dark.
        let lo = (r: 0.61, g: 0.91, b: 0.66)
        let hi = (r: 0.18, g: 0.63, b: 0.26)
        return Color(
            red: lo.r + (hi.r - lo.r) * fraction,
            green: lo.g + (hi.g - lo.g) * fraction,
            blue: lo.b + (hi.b - lo.b) * fraction
        )
    }
}

/// A placeholder bar shown in the contributions cell during the first-ever load, in place
/// of a spinner. Pulses on its own so a board full of them breathes in unison.
struct SkeletonCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.quaternary)
            .frame(width: 30, height: 9)
            .pulsing(true)
    }
}

/// The "refreshing" pulse: opacity eases from 1 down to 0.4 and back, 0.85 s each way, worked
/// out from the time since the pulse began. Not a `repeatForever` animation: switching one off
/// with a nil animation doesn't end it, so it kept redrawing every frame, menu closed or not.
enum PulsePhase {
    static let period: TimeInterval = 1.7
    static let dimmedOpacity = 0.4

    static func opacity(elapsed: TimeInterval) -> Double {
        let cycles = elapsed / period
        let fractionOfCycle = cycles - cycles.rounded(.down)
        let depth = fractionOfCycle < 0.5 ? fractionOfCycle * 2 : (1 - fractionOfCycle) * 2
        let eased = (1 - cos(.pi * depth)) / 2
        return 1 - (1 - dimmedOpacity) * eased
    }

    /// Only while there's something refreshing, motion is allowed, and someone can see it.
    static func shouldPulse(active: Bool, reduceMotion: Bool, hostVisible: Bool) -> Bool {
        active && !reduceMotion && hostVisible
    }
}

extension EnvironmentValues {
    /// Whether the window hosting this view is on screen. The Mac menu bar panel sets it false
    /// while closed, so its views stop all motion instead of redrawing out of sight.
    @Entry var motionHostVisible: Bool = true
}

/// Gently animates opacity while `active`, signalling "this value is refreshing"
/// without a layout-shifting spinner. Settles back to fully opaque when inactive. A paused
/// timeline schedules no frames, so an inactive or hidden pulse costs nothing.
private struct PulseModifier: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motionHostVisible) private var hostVisible
    @State private var startedAt = Date.now

    private var shouldPulse: Bool {
        PulsePhase.shouldPulse(active: active, reduceMotion: reduceMotion, hostVisible: hostVisible)
    }

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shouldPulse)) { context in
            content
                .opacity(shouldPulse ? PulsePhase.opacity(elapsed: context.date.timeIntervalSince(startedAt)) : 1.0)
        }
        .onChange(of: active, initial: true) { _, isActive in
            // Rows that start refreshing together begin at full opacity and breathe in unison.
            if isActive { startedAt = .now }
        }
    }
}

extension View {
    /// Pulse this view's opacity while `active` (e.g. a stale value being refreshed).
    func pulsing(_ active: Bool) -> some View {
        modifier(PulseModifier(active: active))
    }
}
