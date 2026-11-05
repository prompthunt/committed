import ActivityKit
import SwiftUI
import WidgetKit

/// Live rank: your place on the board in the Dynamic Island and on the Lock Screen.
///
/// Every presentation uses tabular numerals and no fixed widths, so it reads in the iPhone Duo's
/// vertical Dynamic Island as well as the standard horizontal one. A missing count shows a
/// placeholder, never zero, and an empty state says what it's waiting for. Once the content passes
/// its stale date (20 minutes after the data), colors step down (lime to deep lime, white to soft,
/// rivals to muted) rather than fading, the Lock Screen's field goes dark, and a clock marks it in
/// every presentation. Tapping opens the Board on Live rank's Window.
struct LiveRankLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveRankAttributes.self) { context in
            LiveRankLockScreen(state: context.state)
                .liveRankStale(context.isStale)
                .widgetURL(context.state.boardURL)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveRankRankLabel(state: state, style: .expanded)
                        .liveRankStale(stale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveRankCountLabel(state: state, style: .expanded)
                        .liveRankStale(stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if state.hasLadder {
                            LiveRankLadder(state: state, showsPassLine: true)
                        } else if state.competitorCount <= 1, let line = state.emptyStateLine {
                            Text(line).font(.subheadline).foregroundStyle(Color.soft)
                        }
                        LiveRankFooter(state: state, showsWindow: false, showsPassLine: false)
                    }
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
            .widgetURL(state.boardURL)
            .keylineTint(.lime)
        }
    }
}

// MARK: - Pieces

/// "–": a count or rank that hasn't loaded. Never shown as 0.
private let placeholder = "–"

private extension LiveRankState {
    /// The ladder needs your count: without it there's nobody to stand between.
    var hasLadder: Bool { competitorCount > 1 && contributions != nil }
}

/// Your rank with the trophy glyph. With no visible rivals there's no rank, just the trophy (and,
/// on the Lock Screen, "Just you so far").
struct LiveRankRankLabel: View {
    enum Style { case compact, minimal, expanded, lockScreen }

    let state: LiveRankState
    let style: Style
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        Group {
            if style == .lockScreen {
                // The Lock Screen's headline stays on one line; the count beside it gives up its
                // caption first when space runs short.
                HStack(alignment: .firstTextBaseline, spacing: 8) { trophy; rankText; extras }
                    .fixedSize()
            } else {
                // The Duo's vertical Dynamic Island is narrow: stack the trophy over the rank
                // there rather than truncating it.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) { trophy; rankText; extras }
                    VStack(spacing: 1) { trophy; rankText; extras }
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
        // The Lock Screen is where people look most: the rank is its headline, as on the Board.
        case .lockScreen: CommittedType.display(36, relativeTo: .largeTitle)
        // Expanded keeps the original title3 metrics: the island's leading region is narrow, and
        // anything bigger stacks the trophy, rank, and movement and pushes the ladder out.
        case .expanded: CommittedType.display(20, relativeTo: .title3)
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
    @ScaledMetric(relativeTo: .title3) private var expandedTrophy: CGFloat = 19
    @ScaledMetric(relativeTo: .title) private var lockScreenTrophy: CGFloat = 28
    private var trophySize: CGFloat {
        switch style {
        case .lockScreen: lockScreenTrophy
        case .expanded: expandedTrophy
        case .compact, .minimal: compactTrophy
        }
    }

    @ViewBuilder private var rankText: some View {
        if let rank = state.rank {
            Text("#\(rank)")
                .displayTracking(style == .lockScreen ? 36 : 0)
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

    @ViewBuilder private var extras: some View {
        if style == .expanded || style == .lockScreen, state.rank != nil {
            Text("of \(state.competitorCount)")
                .font(style == .lockScreen
                      ? CommittedType.numeral(17, relativeTo: .headline)
                      : CommittedType.numeral(15, relativeTo: .subheadline))
                .foregroundStyle(isStale ? Color.muted : Color.soft)
            if state.movementToday != 0 {
                // Today's movement since the morning, like the board's chevrons.
                Label("\(abs(state.movementToday))",
                      systemImage: state.movementToday > 0 ? "chevron.up" : "chevron.down")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(movementColor)
                    .monospacedDigit()
            }
        }
    }

    private var movementColor: Color {
        if state.movementToday > 0 { return isStale ? .limeDeep : .lime }
        return isStale ? .muted : .soft
    }
}

/// Your Contributions for the Window.
struct LiveRankCountLabel: View {
    enum Style { case compact, expanded, lockScreen }

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
                    // Stale without relying on brightness: a clock beside the count.
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warning)
                        .accessibilityHidden(true)
                }
                Text(state.contributions.map { "\($0)" } ?? placeholder)
                    .foregroundStyle(isStale ? Color.limeDeep : Color.lime)
                    .displayTracking(style == .lockScreen ? 40 : 0)
                if style == .expanded {
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
        case .expanded: CommittedType.display(20, relativeTo: .title3)
        case .compact: CommittedType.display(16, relativeTo: .body)
        }
    }
}

/// You between the people directly above and below, then (in the island) the gap to pass the
/// person ahead. The Lock Screen puts that line in its footer.
struct LiveRankLadder: View {
    let state: LiveRankState
    let showsPassLine: Bool
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let above = state.above {
                LiveRankLadderRow(rank: state.rank.map { $0 - 1 }, login: above.login,
                                  contributions: above.contributions, isYou: false)
            }
            LiveRankLadderRow(rank: state.rank, login: "You", contributions: state.contributions, isYou: true)
            if let below = state.below {
                LiveRankLadderRow(rank: state.rank.map { $0 + 1 }, login: below.login,
                                  contributions: below.contributions, isYou: false)
            }
            if showsPassLine, let line = LiveRankText.passLine(state) {
                Text(line)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isStale ? Color.limeDeep : Color.lime)
                    .monospacedDigit()
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }
}

struct LiveRankLadderRow: View {
    let rank: Int?
    let login: String
    let contributions: Int?
    let isYou: Bool
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        // Wraps the count under the name rather than truncating when space runs out (vertical
        // Dynamic Island, large text).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { rankText; name; Spacer(minLength: 8); count }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) { rankText; name }
                count
            }
        }
        .font(isYou ? CommittedType.display(15, relativeTo: .subheadline) : CommittedType.numeral(15, relativeTo: .subheadline))
        // Soft for rivals, not muted: on the Lock Screen they sit over the field.
        .foregroundStyle(textColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveRankText.rowAccessibility(rank: rank, login: login, contributions: contributions))
    }

    private var textColor: Color {
        switch (isYou, isStale) {
        case (true, false): .white
        case (true, true): .soft
        case (false, false): .soft
        case (false, true): .muted
        }
    }

    private var rankText: some View {
        Text(rank.map { "#\($0)" } ?? placeholder)
    }

    private var name: some View {
        // Logins in San Francisco, like the board's rows; numbers in Inter Tight.
        Text(login).font(.subheadline.weight(isYou ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
    }

    private var count: some View {
        Text(contributions.map { "\($0)" } ?? placeholder)
            .foregroundStyle(isYou ? (isStale ? Color.limeDeep : Color.lime) : textColor)
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

/// Lock Screen: your rank as the headline beside your count, the ladder, then the Window, the
/// refresh age, and the gap to pass. The site's lit field sits behind the count while the numbers
/// are fresh, and goes dark when they're stale.
struct LiveRankLockScreen: View {
    let state: LiveRankState
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                LiveRankRankLabel(state: state, style: .lockScreen)
                Spacer(minLength: 8)
                if state.contributions != nil || state.competitorCount <= 1 {
                    LiveRankCountLabel(state: state, style: .lockScreen)
                }
            }
            if state.hasLadder {
                LiveRankLadder(state: state, showsPassLine: false)
            }
            LiveRankFooter(state: state, showsWindow: true, showsPassLine: true)
        }
        // The card is a fixed height: past accessibility 1 the headline would clip.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(alignment: .topTrailing) {
            if !isStale {
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

    static func rowAccessibility(rank: Int?, login: String, contributions: Int?) -> String {
        let place = rank.map { "Rank \($0), " } ?? ""
        let count = contributions.map { "\($0) contributions" } ?? "contributions not loaded"
        return "\(place)\(login), \(count)"
    }
}

// MARK: - Previews

#if DEBUG
extension LiveRankState {
    static let previewMiddle = LiveRankState(
        window: "daily", rank: 3, competitorCount: 6, contributions: 7,
        above: .init(login: "priya-s", contributions: 9), below: .init(login: "devon-k", contributions: 6),
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
