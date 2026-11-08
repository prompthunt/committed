import ActivityKit
import SwiftUI
import WidgetKit

/// Live rank: your place on the board in the Dynamic Island and on the Lock Screen.
///
/// The expanded island and the Lock Screen list the person above you, you, and the person below
/// in the board's own row (`LiveRankRows`); the row carries the rank, so there's no separate
/// headline. Compact and minimal show your rank and count.
///
/// Every presentation uses tabular numerals and no fixed widths, so it reads in the iPhone Duo's
/// vertical Dynamic Island as well as the standard horizontal one. A missing count shows a
/// placeholder, never zero, and an empty state says what it's waiting for. Once the content passes
/// its stale date (20 minutes after the data), colors step down (lime to deep lime, white to soft)
/// rather than fading, the Lock Screen's field goes dark, and a clock marks it in every
/// presentation. Tapping opens the Board on Live rank's Window.
struct LiveRankLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveRankAttributes.self) { context in
            LiveRankActivityContent(state: context.state, selfLogin: context.attributes.selfLogin)
                .liveRankStale(context.isStale)
                .widgetURL(context.state.boardURL)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                // Beside the sensor: the trophy and the Window, then the gap to pass (or, with
                // no rows to show, your count).
                // Both corners sit inward from their regions' edges: flush, the island's corner
                // curve clipped the trophy and the region's edge shaved the pass line's last glyph.
                // The trailing 10 pt also ends the pass line where the rows' squares end.
                DynamicIslandExpandedRegion(.leading) {
                    LiveRankWindowLabel(state: state)
                        .padding(.leading, 12)
                        .liveRankStale(stale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if state.hasLadder {
                            LiveRankPassLine(state: state)
                        } else {
                            LiveRankCountLabel(state: state, style: .expanded)
                        }
                    }
                    .padding(.trailing, 10)
                    .liveRankStale(stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if state.hasLadder {
                            LiveRankRows(state: state, selfLogin: context.attributes.selfLogin)
                        } else if state.competitorCount <= 1, let line = state.emptyStateLine {
                            Text(line).font(.subheadline).foregroundStyle(Color.soft)
                        }
                        // The corners already carry the Window and the gap to pass, so the
                        // footer only appears with something to add: staleness or a missing count.
                        if LiveRankFooter.showsStatus(state, showsWindow: false, isStale: stale) {
                            LiveRankFooter(state: state, showsWindow: false, showsPassLine: false)
                        }
                    }
                    // A fixed-height presentation: three rows must not wrap off the bottom.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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

/// The expanded island's leading corner: the trophy and Live rank's Window ("TODAY").
struct LiveRankWindowLabel: View {
    let state: LiveRankState
    @Environment(\.liveRankIsStale) private var isStale
    @ScaledMetric(relativeTo: .footnote) private var trophySize: CGFloat = 15

    var body: some View {
        HStack(spacing: 6) {
            TrophyMark(size: trophySize, color: isStale ? .limeDeep : .lime)
            if let window = state.contributionWindow {
                Text(window.shortTitle)
                    .eyebrow()
                    .foregroundStyle(isStale ? Color.warning : Color.soft)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.contributionWindow.map { "Live rank, \($0.accessibilityDescription)" } ?? "Live rank")
    }
}

/// "3 to pass alice", in lime: the island's trailing corner, beside the rows.
struct LiveRankPassLine: View {
    let state: LiveRankState
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        if let line = LiveRankText.passLine(state) {
            Text(line)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isStale ? Color.limeDeep : Color.lime)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.middle)
        }
    }
}

/// Your rank with the trophy glyph. With no visible rivals there's no rank, just the trophy (and,
/// on the Lock Screen, "Just you so far").
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

    /// The Committed trophy in lime, sized with the rank beside it.
    @ViewBuilder private var trophy: some View {
        if style != .minimal || state.rank == nil {
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
                if isStale, style == .compact || style == .small {
                    // Stale without relying on brightness: a clock beside the count.
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

/// The Window, then "Updated 4 minutes ago" once there's data ("Waiting for your first count"
/// before), and on the Lock Screen the gap to pass. The age is a live date-driven `Text`, so it
/// keeps counting between updates without the app running.
struct LiveRankFooter: View {
    let state: LiveRankState
    let showsWindow: Bool
    let showsPassLine: Bool
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        // One line, so the Lock Screen card stays inside its height: the Window, the gap to pass,
        // then the refresh age, which shrinks a little before anything truncates.
        HStack(spacing: 8) {
            if showsWindow, let window = state.contributionWindow {
                Text(window.shortTitle).fontWeight(.medium)
                    .foregroundStyle(isStale ? Color.warning : Color.soft)
                    .fixedSize()
            }
            if showsPassLine, let line = LiveRankText.passLine(state) {
                Text(line)
                    .fontWeight(.semibold)
                    .foregroundStyle(isStale ? Color.limeDeep : Color.lime)
                    .monospacedDigit()
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
            status
                .minimumScaleFactor(0.8)
        }
        .font(.caption)
        .lineLimit(1)
    }

    /// Whether the status (refresh age, or what it's waiting for) has anything to say.
    static func showsStatus(_ state: LiveRankState, showsWindow: Bool, isStale: Bool) -> Bool {
        (state.contributions == nil && state.competitorCount > 1 && state.emptyStateLine != nil)
            || showsWindow || isStale
    }

    @ViewBuilder private var status: some View {
        if state.contributions == nil, state.competitorCount > 1, let line = state.emptyStateLine {
            // No count yet: say so, rather than "Updated" beside dashes.
            Text(line)
                .foregroundStyle(isStale ? Color.warning : Color.soft)
        } else if showsWindow || isStale {
            HStack(spacing: 3) {
                if isStale {
                    Image(systemName: "clock.badge.exclamationmark").accessibilityHidden(true)
                }
                Text("Updated \(Text(.currentDate, format: .reference(to: state.updatedDate, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)))")
                    .monospacedDigit()
            }
            .foregroundStyle(isStale ? Color.warning : Color.soft)
        }
    }
}

/// Lock Screen: the people above and below you in the board's rows, then the Window, the gap to
/// pass, and the refresh age. Without rows (no rivals, or no count yet), the trophy and your count
/// head the card instead, over the site's lit field, which goes dark when the numbers are stale.
/// The rows sit on plain ink: their squares glyph is a mark that has to keep 3:1, and the field's
/// lit squares would take that away.
struct LiveRankLockScreen: View {
    let state: LiveRankState
    let selfLogin: String
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.hasLadder {
                LiveRankRows(state: state, selfLogin: selfLogin)
                    // Line the rows' content up with the footer's text.
                    .padding(.horizontal, -10)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    LiveRankRankLabel(state: state, style: .lockScreen)
                    Spacer(minLength: 8)
                    if state.contributions != nil || state.competitorCount <= 1 {
                        LiveRankCountLabel(state: state, style: .lockScreen)
                    }
                }
            }
            LiveRankFooter(state: state, showsWindow: true, showsPassLine: true)
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
/// from the driver's seat, so there are no rows. Your rank and count sit on one line, then the gap
/// to pass ("3 to pass alice"), or what Live rank is waiting for. Stale content steps its colors
/// down and puts the clock beside the count. CarPlay doesn't run buttons; a tap on iPhone opens
/// the Board.
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
            // One line, never two facts: the refresh age doesn't fit beside the gap at this size,
            // and the clock and stepped-down colors already mark stale numbers.
            if state.hasLadder {
                LiveRankPassLine(state: state)
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

    static func countAccessibility(_ state: LiveRankState) -> String {
        guard let contributions = state.contributions else { return "Contributions not loaded" }
        return contributions == 1 ? "1 contribution" : "\(contributions) contributions"
    }
}

// MARK: - Previews

#if DEBUG
extension LiveRankState {
    static let previewMiddle = LiveRankState(
        window: "daily", rank: 3, competitorCount: 6, contributions: 7,
        above: .init(login: "priya-s", contributions: 9, movementToday: 0),
        below: .init(login: "devon-k", contributions: 6, movementToday: -1),
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

#Preview("Lock Screen", as: .content, using: LiveRankAttributes(selfLogin: "sam-rivera")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
    LiveRankState.previewNoRivals
    LiveRankState.previewNoData
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: LiveRankAttributes(selfLogin: "sam-rivera")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
}

#Preview("Compact", as: .dynamicIsland(.compact), using: LiveRankAttributes(selfLogin: "sam-rivera")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
    LiveRankState.previewNoRivals
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: LiveRankAttributes(selfLogin: "sam-rivera")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
}
#endif
