import ActivityKit
import SwiftUI
import WidgetKit

/// Live rank: your place on the board in the Dynamic Island and on the Lock Screen.
///
/// The expanded island and the Lock Screen list the person above you, you, and the person below
/// in the board's own row (`LiveRankRows`); the row carries the rank, so there's no separate
/// headline. Over the rows sit the trophy and the Window ("Today") and, on the right, how long ago
/// the numbers were updated ("13 min, 36 sec"), counting up live between updates. Compact and
/// minimal show your rank and count.
///
/// Every presentation uses tabular numerals and no fixed widths, so it reads in the iPhone Duo's
/// vertical Dynamic Island as well as the standard horizontal one. A missing count shows a
/// placeholder, never zero, and an empty state says what it's waiting for. Once the content passes
/// its stale date (20 minutes after the data), colors step down (lime to deep lime, white to soft)
/// rather than fading, the Lock Screen's field goes dark, and compact's count
/// gets a clock, since it has no room for the age. Tapping opens the Board on Live rank's Window.
struct LiveRankLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveRankAttributes.self) { context in
            LiveRankActivityContent(state: context.state, selfLogin: context.attributes.selfLogin)
                .liveRankStale(context.isStale)
                // The Sample board's made-up people show initials, never a saved avatar.
                .environment(\.savedAvatars, context.attributes.savedAvatars)
                .widgetURL(context.state.boardURL)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveRankIslandLeading(state: state)
                        .liveRankStale(stale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveRankIslandTrailing(state: state)
                        .liveRankStale(stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveRankIslandBottom(state: state, selfLogin: context.attributes.selfLogin)
                        .environment(\.savedAvatars, context.attributes.savedAvatars)
                        .liveRankStale(stale)
                }
            } compactLeading: {
                LiveRankRankLabel(state: state, style: .compact)
                    .liveRankStale(stale)
            } compactTrailing: {
                LiveRankCountLabel(state: state, style: .compact)
                    .liveRankStale(stale)
            } minimal: {
                LiveRankRankLabel(state: state, style: .minimal)
                    .liveRankStale(stale)
            }
            // The default bottom margin left more room under the rows than between them; this
            // keeps the island inside its 160 pt cap with the rows' wider spacing.
            .contentMargins(.bottom, 12, for: .expanded)
            .widgetURL(state.boardURL)
            .keylineTint(.lime)
        }
        // The small family is what the CarPlay dashboard and Apple Watch's Smart Stack show.
        // Committed isn't a CarPlay app; supporting this family is all CarPlay needs.
        .supplementalActivityFamilies([.small])
    }
}

/// The Live Activity's non-island content, by family: the Lock Screen card, or the small layout
/// that CarPlay and Apple Watch show.
struct LiveRankActivityContent: View {
    let state: LiveRankState
    let selfLogin: String
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            LiveRankSmall(state: state)
        default:
            LiveRankLockScreen(state: state, selfLogin: selfLogin)
        }
    }
}

// MARK: - Pieces

/// "–": a count or rank that hasn't loaded. Never shown as 0.
private let placeholder = "–"

extension LiveRankState {
    /// The rows need your count: without it there's nobody to stand between.
    var hasLadder: Bool { competitorCount > 1 && contributions != nil }
}

/// The trophy and the Window ("Today", "7 days", "30 days") at 16 pt, heading Live rank and every
/// system-size widget.
struct LiveRankWindowLabel: View {
    let state: LiveRankState
    var accessibilityName = "Live rank"
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        HStack(spacing: 6) {
            TrophyMark(size: 17, color: isStale ? .limeDeep : .lime)
            if let window = state.contributionWindow {
                Text(window.shortTitle)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.soft)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.contributionWindow.map { "\(accessibilityName), \($0.accessibilityDescription)" } ?? accessibilityName)
    }
}

/// How long ago the numbers were updated, at 12 pt: "13 min, 36 sec", counting up every second
/// without a reload (a date-relative `Text`), so you can tell at a glance whether they're current.
/// Always soft grey: its value says how old the numbers are. Left out of Share board's images
/// (`showsUpdateAge`), where a still frozen at one moment would mislead.
struct UpdateAge: View {
    let date: Date
    @Environment(\.showsUpdateAge) private var showsUpdateAge

    var body: some View {
        if showsUpdateAge {
            Text(date, style: .relative)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.soft)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .accessibilityLabel(Text("Updated \(Text(date, style: .relative)) ago"))
        }
    }
}

/// The Window on the left, the age on the right, on one baseline: the head of Live rank's Lock
/// Screen card and of the medium and large widgets.
struct LiveRankHeader: View {
    let state: LiveRankState
    var accessibilityName = "Live rank"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            LiveRankWindowLabel(state: state, accessibilityName: accessibilityName)
            Spacer(minLength: 8)
            UpdateAge(date: state.updatedDate)
        }
    }
}

/// The expanded island's leading corner: the trophy and the Window. Inset from the region's edge:
/// flush, the island's corner curve clipped the trophy.
struct LiveRankIslandLeading: View {
    let state: LiveRankState

    var body: some View {
        LiveRankWindowLabel(state: state)
            .padding(.leading, 12)
    }
}

/// The expanded island's trailing corner: the age, or, with no rows to show, your count. The 10 pt
/// inset ends it where the rows' squares end.
struct LiveRankIslandTrailing: View {
    let state: LiveRankState

    var body: some View {
        Group {
            if state.hasLadder {
                UpdateAge(date: state.updatedDate)
            } else {
                LiveRankCountLabel(state: state, style: .expanded)
            }
        }
        .padding(.trailing, 10)
    }
}

/// The expanded island's bottom: the rows, or what Live rank is waiting for.
struct LiveRankIslandBottom: View {
    let state: LiveRankState
    let selfLogin: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.hasLadder {
                LiveRankRows(state: state, selfLogin: selfLogin)
            } else {
                if state.competitorCount <= 1, let line = state.emptyStateLine {
                    // Just you: your streak on this line, so the island keeps its height.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(line).font(.subheadline).foregroundStyle(Color.soft)
                        Spacer(minLength: 8)
                        LiveRankStreak(state: state, size: 15)
                    }
                }
                // The corners carry the Window and the count; the age goes here.
                LiveRankStatusLine(state: state)
            }
        }
        // A fixed-height presentation: three rows must not wrap off the bottom.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Your rank with the trophy glyph (on the Lock Screen and the medium widget, the header has the
/// trophy). With no visible rivals there's no rank, just the trophy (on the Lock Screen, "Just you
/// so far").
struct LiveRankRankLabel: View {
    enum Style { case compact, minimal, small, lockScreen }

    let state: LiveRankState
    let style: Style
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        Group {
            if style == .lockScreen {
                // Only without rows (no rivals, or no count yet): the trophy and what it's
                // waiting for, on one line beside the count.
                HStack(alignment: .firstTextBaseline, spacing: 8) { trophy; rankText }
                    .fixedSize()
            } else {
                // The Duo's vertical Dynamic Island is narrow: stack the trophy over the rank
                // there rather than truncating it.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) { trophy; rankText }
                    VStack(spacing: 1) { trophy; rankText }
                }
            }
        }
        .font(font)
        .foregroundStyle(isStale ? Color.muted : .white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveRankText.rankAccessibility(state))
    }

    private var font: Font {
        switch style {
        case .lockScreen: CommittedType.display(36, relativeTo: .largeTitle)
        case .small: CommittedType.display(26, relativeTo: .title)
        case .compact, .minimal: CommittedType.display(16, relativeTo: .body)
        }
    }

    /// The Committed trophy in lime, sized with the rank beside it. Not on the Lock Screen card or
    /// the medium widget, whose header already carries it.
    @ViewBuilder private var trophy: some View {
        if style != .lockScreen, style != .minimal || state.rank == nil {
            let size = trophySize
            TrophyMark(size: size, color: isStale ? .limeDeep : .lime)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - size * 0.12 }
        }
    }

    @ScaledMetric(relativeTo: .body) private var compactTrophy: CGFloat = 16
    @ScaledMetric(relativeTo: .title) private var lockScreenTrophy: CGFloat = 28
    @ScaledMetric(relativeTo: .title) private var smallTrophy: CGFloat = 22
    private var trophySize: CGFloat {
        switch style {
        case .lockScreen: lockScreenTrophy
        case .small: smallTrophy
        case .compact, .minimal: compactTrophy
        }
    }

    @ViewBuilder private var rankText: some View {
        if let rank = state.rank {
            Text("#\(rank)")
        } else if style == .lockScreen, state.competitorCount <= 1, let line = state.emptyStateLine {
            Text(line)
                .font(.headline)
                .foregroundStyle(isStale ? Color.muted : Color.soft)
        } else if state.competitorCount > 1, style != .lockScreen {
            // Rivals but no count of yours yet. The dash takes a rank's width, so the island
            // lays out the same as when there is one (trophy over the rank on the Duo).
            Text("#8").hidden().overlay { Text(placeholder) }
        }
    }
}

/// Your streak (the mark and "14", from 2 days) where Live rank has no rows to carry it: the Lock Screen card
/// and the expanded island when nobody else is on your board. Nothing without your count
/// (`state.streak` is nil then) or under 2 days.
struct LiveRankStreak: View {
    let state: LiveRankState
    let size: CGFloat
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        StreakBadge(streak: state.streak, markSize: size * 0.9, relativeTo: .subheadline,
                    markColor: isStale ? Color.rowGlyphs[1] : .limeDeep)
            .font(CommittedType.numeral(size, relativeTo: .subheadline))
            .foregroundStyle(isStale ? Color.muted : Color.soft)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Your Contributions for the Window.
struct LiveRankCountLabel: View {
    enum Style { case compact, expanded, small, lockScreen }

    let state: LiveRankState
    let style: Style
    @Environment(\.liveRankIsStale) private var isStale
    @ScaledMetric(relativeTo: .title3) private var squareSize: CGFloat = 12

    var body: some View {
        Group {
            if style == .lockScreen {
                // The caption on the count's baseline, so the card stays inside the Lock Screen's
                // height; dropped (VoiceOver still says it) when a long count needs the room.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { caption; number.font(font) }
                    number.font(font)
                }
            } else {
                row
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveRankText.countAccessibility(state) + (isStale && style == .compact ? ", out of date" : ""))
    }

    private var number: some View {
        Text(state.contributions.map { "\($0)" } ?? placeholder)
            .foregroundStyle(isStale ? Color.limeDeep : Color.lime)
            .displayTracking(style == .lockScreen ? 36 : 0)
    }

    private var caption: some View {
        Text("Contributions")
            .eyebrow()
            .foregroundStyle(isStale ? Color.muted : Color.soft)
            .fixedSize()
    }

    private var row: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .center, spacing: 5) {
                if isStale, style == .compact {
                    // Stale without relying on brightness: a clock beside the count, since
                    // compact has no room for the age.
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warning)
                        .accessibilityHidden(true)
                }
                Text(state.contributions.map { "\($0)" } ?? placeholder)
                    .foregroundStyle(isStale ? Color.limeDeep : Color.lime)
                    .displayTracking(style == .lockScreen ? 40 : 0)
                if style == .expanded || style == .small {
                    // One lit square of the contribution graph.
                    ContributionSquare(level: state.contributions.map { $0 > 0 ? (isStale ? 3 : 4) : 0 } ?? 0,
                                       size: squareSize)
                }
            }
            .font(font)
        }
    }

    private var font: Font {
        switch style {
        case .lockScreen: CommittedType.display(36, relativeTo: .largeTitle)
        case .small: CommittedType.display(26, relativeTo: .title)
        case .expanded: CommittedType.display(20, relativeTo: .title3)
        case .compact: CommittedType.display(16, relativeTo: .body)
        }
    }
}

/// One line under the rows' place: what Live rank is waiting for before your count loads
/// ("Waiting for your first count"), otherwise the age.
struct LiveRankStatusLine: View {
    let state: LiveRankState
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        if let line = Self.waiting(state) {
            Text(line)
                .font(.caption)
                .foregroundStyle(isStale ? Color.warning : Color.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            UpdateAge(date: state.updatedDate)
        }
    }

    /// Rivals but no count of yours yet: say so, rather than an age beside dashes.
    static func waiting(_ state: LiveRankState) -> String? {
        state.contributions == nil && state.competitorCount > 1 ? state.emptyStateLine : nil
    }
}

/// Lock Screen: the trophy and the Window with the age on the right, as the medium widget heads
/// itself, then the people above and below you in the board's rows. Without rows (no rivals, or no
/// count yet), your rank and count take their place, over the site's lit field,
/// which goes dark when the numbers are stale. The rows sit on plain ink: their squares glyph is a
/// mark that has to keep 3:1, and the field's lit squares would take that away.
struct LiveRankLockScreen: View {
    let state: LiveRankState
    let selfLogin: String
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LiveRankHeader(state: state)
            if state.hasLadder {
                LiveRankRows(state: state, selfLogin: selfLogin)
                    // Line the rows' content up with the header's.
                    .padding(.horizontal, -10)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    LiveRankRankLabel(state: state, style: .lockScreen)
                    Spacer(minLength: 8)
                    // Just you: your streak beside your count, on the same line (the card's
                    // height is capped).
                    LiveRankStreak(state: state, size: 17)
                    if state.contributions != nil || state.competitorCount <= 1 {
                        LiveRankCountLabel(state: state, style: .lockScreen)
                    }
                }
                if let line = LiveRankStatusLine.waiting(state) {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(isStale ? Color.warning : Color.soft)
                        .lineLimit(1)
                }
            }
        }
        // The card is a fixed height: past accessibility 1 the headline would clip, and the
        // rows would wrap long names off the bottom.
        .dynamicTypeSize(...(state.hasLadder ? DynamicTypeSize.xxLarge : .accessibility1))
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(alignment: .topTrailing) {
            if !isStale, !state.hasLadder {
                // The site's lit square field, still, behind the count. Text over it is white,
                // soft, or lime (`FieldTone.lockScreen`, checked in `ThemeTests`).
                SquareFieldCanvas(light: UnitPoint(x: 0.95, y: 0), reach: 0.5, cell: 12, gap: 3, tone: .lockScreen)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
            }
        }
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(.ink)
        .activitySystemActionForegroundColor(.lime)
    }
}

/// The small family: the CarPlay dashboard and Apple Watch's Smart Stack. It's read at a glance
/// from the driver's seat, so there are no rows. Your rank and count sit on one line, then the
/// Window and the age, or what Live rank is waiting for. Stale content steps its colors down.
/// CarPlay doesn't run buttons; a tap on iPhone opens the Board.
struct LiveRankSmall: View {
    let state: LiveRankState
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                LiveRankRankLabel(state: state, style: .small)
                Spacer(minLength: 8)
                if state.contributions != nil || state.competitorCount <= 1 {
                    LiveRankCountLabel(state: state, style: .small)
                }
            }
            if state.hasLadder {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let window = state.contributionWindow {
                        Text(window.shortTitle)
                            .font(.footnote)
                            .foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 4)
                    UpdateAge(date: state.updatedDate)
                }
            } else if let line = state.emptyStateLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(isStale ? Color.muted : Color.soft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        // A fixed, small surface: two lines must not wrap.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(.ink)
    }
}

extension EnvironmentValues {
    /// Live rank's content is past its stale date.
    @Entry var liveRankIsStale = false
    /// Whether `UpdateAge` shows. Share board's images turn it off.
    @Entry var showsUpdateAge = true
}

private extension View {
    /// Stale numbers step down in color (see `LiveRankLiveActivity`), never in opacity, so they
    /// keep their contrast.
    func liveRankStale(_ isStale: Bool) -> some View {
        environment(\.liveRankIsStale, isStale)
    }
}

// MARK: - Copy

enum LiveRankText {
    /// "3 to pass alice".
    static func passLine(_ state: LiveRankState) -> String? { state.passLine }

    static func rankAccessibility(_ state: LiveRankState) -> String {
        if let rank = state.rank {
            let moved = state.movementToday == 0 ? "" :
                ", \(state.movementToday > 0 ? "up" : "down") \(abs(state.movementToday)) today"
            return "Rank \(rank) of \(state.competitorCount)\(moved)"
        }
        return state.competitorCount > 1 ? "Rank not loaded" : "Live rank"
    }

    /// "12 contributions", and with `streak`, ", 5-day streak" when your streak shows (the small
    /// widget, which shows it beside your count).
    static func countAccessibility(_ state: LiveRankState, streak: Bool = false) -> String {
        guard let contributions = state.contributions else { return "Contributions not loaded" }
        let count = contributions == 1 ? "1 contribution" : "\(contributions) contributions"
        guard streak, let spoken = StreakLabel.spoken(state.streak) else { return count }
        return "\(count), \(spoken)"
    }
}

// MARK: - Previews

#if DEBUG
extension LiveRankState {
    static let previewMiddle = LiveRankState(
        window: "daily", rank: 3, competitorCount: 6, contributions: 7,
        above: .init(login: "odile-m", contributions: 9, movementToday: 0),
        below: .init(login: "ezra-q", contributions: 6, movementToday: -1),
        movementToday: 1, updatedAt: Int(Date().timeIntervalSince1970) - 240
    )
    static let previewNoRivals = LiveRankState(
        window: "weekly", rank: nil, competitorCount: 1, contributions: 38,
        above: nil, below: nil, movementToday: 0, updatedAt: Int(Date().timeIntervalSince1970) - 60
    )
    static let previewNoData = LiveRankState(
        window: "daily", rank: nil, competitorCount: 6, contributions: nil,
        above: nil, below: nil, movementToday: 0, updatedAt: Int(Date().timeIntervalSince1970)
    )
}

#Preview("Lock Screen", as: .content, using: LiveRankAttributes(selfLogin: "ari-linden")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
    LiveRankState.previewNoRivals
    LiveRankState.previewNoData
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: LiveRankAttributes(selfLogin: "ari-linden")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
}

#Preview("Compact", as: .dynamicIsland(.compact), using: LiveRankAttributes(selfLogin: "ari-linden")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
    LiveRankState.previewNoRivals
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: LiveRankAttributes(selfLogin: "ari-linden")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
}
#endif
