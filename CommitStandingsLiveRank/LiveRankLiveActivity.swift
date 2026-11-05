import ActivityKit
import SwiftUI
import WidgetKit

/// Live rank: your place on the board in the Dynamic Island and on the Lock Screen.
///
/// Every presentation uses tabular numerals and no fixed widths, so it reads in the iPhone Duo's
/// vertical Dynamic Island as well as the standard horizontal one. A missing count shows a
/// placeholder, never zero. Once the content passes its stale date (20 minutes after the data),
/// numbers dim and the refresh age shows. Tapping opens the Board on Live rank's Window.
struct LiveRankLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveRankAttributes.self) { context in
            LiveRankLockScreen(state: context.state, isStale: context.isStale)
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
                    LiveRankCountLabel(state: state, showsUnit: true)
                        .liveRankStale(stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        LiveRankLadder(state: state)
                        LiveRankFooter(state: state, isStale: stale, showsWindow: false)
                    }
                    .liveRankStale(stale)
                }
            } compactLeading: {
                LiveRankRankLabel(state: state, style: .compact)
                    .liveRankStale(stale)
            } compactTrailing: {
                LiveRankCountLabel(state: state, showsUnit: false)
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

/// Your rank with the trophy glyph. With no visible rivals there's no rank, just the trophy.
struct LiveRankRankLabel: View {
    enum Style { case compact, minimal, expanded }

    let state: LiveRankState
    let style: Style

    var body: some View {
        // The Duo's vertical Dynamic Island is narrow: stack the trophy over the rank there
        // rather than truncating it.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) { trophy; rankText; extras }
            VStack(spacing: 1) { trophy; rankText; extras }
        }
        .font(style == .expanded
              ? CommittedType.display(24, relativeTo: .title2)
              : CommittedType.display(16, relativeTo: .body))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveRankText.rankAccessibility(state))
    }

    /// The Committed trophy in lime, sized with the rank beside it.
    @ViewBuilder private var trophy: some View {
        if style != .minimal || state.rank == nil {
            TrophyMark(size: trophySize)
        }
    }

    @ScaledMetric(relativeTo: .body) private var compactTrophy: CGFloat = 16
    @ScaledMetric(relativeTo: .title2) private var expandedTrophy: CGFloat = 24
    private var trophySize: CGFloat { style == .expanded ? expandedTrophy : compactTrophy }

    @ViewBuilder private var rankText: some View {
        if let rank = state.rank {
            Text("#\(rank)")
        } else if state.competitorCount > 1 {
            // Rivals but no count of yours yet.
            Text(placeholder)
        }
    }

    @ViewBuilder private var extras: some View {
        if style == .expanded, state.rank != nil {
            Text("of \(state.competitorCount)")
                .font(CommittedType.numeral(17, relativeTo: .body))
                .foregroundStyle(Color.muted)
            if state.movementToday != 0 {
                // Today's movement since the morning, like the board's chevrons.
                Label("\(abs(state.movementToday))",
                      systemImage: state.movementToday > 0 ? "chevron.up" : "chevron.down")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(state.movementToday > 0 ? Color.lime : Color.muted)
                    .monospacedDigit()
            }
        }
    }
}

/// Your Contributions for the Window.
struct LiveRankCountLabel: View {
    let state: LiveRankState
    let showsUnit: Bool
    @ScaledMetric(relativeTo: .title2) private var squareSize: CGFloat = 13

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Text(state.contributions.map { "\($0)" } ?? placeholder)
                .foregroundStyle(Color.lime)
            if showsUnit {
                // One lit square of the contribution graph.
                ContributionSquare(level: state.contributions.map { $0 > 0 ? 4 : 0 } ?? 0, size: squareSize)
            }
        }
        .font(showsUnit
              ? CommittedType.display(24, relativeTo: .title2)
              : CommittedType.display(16, relativeTo: .body))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveRankText.countAccessibility(state))
    }
}

/// You between the people directly above and below, then the gap to pass the person ahead.
struct LiveRankLadder: View {
    let state: LiveRankState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let above = state.above {
                LiveRankLadderRow(rank: state.rank.map { $0 - 1 }, login: above.login,
                                  contributions: above.contributions, isYou: false)
            }
            LiveRankLadderRow(rank: state.rank, login: "You", contributions: state.contributions, isYou: true)
            if let below = state.below {
                LiveRankLadderRow(rank: state.rank.map { $0 + 1 }, login: below.login,
                                  contributions: below.contributions, isYou: false)
            }
            if let line = LiveRankText.passLine(state) {
                Text(line)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.lime)
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
        .foregroundStyle(isYou ? Color.white : Color.muted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveRankText.rowAccessibility(rank: rank, login: login, contributions: contributions))
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
            .foregroundStyle(isYou ? Color.lime : Color.muted)
    }
}

/// The Window and "Updated 4 minutes ago". The age is a live date-driven `Text`, so it keeps
/// counting between updates without the app running.
struct LiveRankFooter: View {
    let state: LiveRankState
    let isStale: Bool
    let showsWindow: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { content }
            VStack(alignment: .leading, spacing: 2) { content }
        }
        .font(.caption)
        .foregroundStyle(isStale ? Color.warning : Color.muted)
        .lineLimit(1)
    }

    @ViewBuilder private var content: some View {
        if showsWindow, let window = state.contributionWindow {
            Text(window.shortTitle).fontWeight(.medium)
        }
        if showsWindow || isStale {
            HStack(spacing: 3) {
                if isStale {
                    Image(systemName: "clock.badge.exclamationmark").accessibilityHidden(true)
                }
                Text("Updated \(Text(.currentDate, format: .reference(to: state.updatedDate, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)))")
                    .monospacedDigit()
            }
        }
    }
}

/// Lock Screen: the expanded Dynamic Island's content on a larger card, plus the Window and the
/// refresh age.
struct LiveRankLockScreen: View {
    let state: LiveRankState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                LiveRankRankLabel(state: state, style: .expanded)
                Spacer(minLength: 8)
                LiveRankCountLabel(state: state, showsUnit: true)
            }
            .liveRankStale(isStale)
            if state.competitorCount > 1 {
                LiveRankLadder(state: state)
                    .liveRankStale(isStale)
            }
            LiveRankFooter(state: state, isStale: isStale, showsWindow: true)
        }
        .padding()
        .background(alignment: .topTrailing) {
            // The site's lit square field, still, behind the count.
            SquareFieldCanvas(light: UnitPoint(x: 0.95, y: 0), reach: 0.5, cell: 12, gap: 3, brightness: 0.55, maxLevel: 3)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
        }
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(.ink)
        .activitySystemActionForegroundColor(.lime)
    }
}

private extension View {
    /// Stale numbers dim; the footer says how old they are.
    func liveRankStale(_ isStale: Bool) -> some View {
        opacity(isStale ? 0.45 : 1)
    }
}

// MARK: - Copy

enum LiveRankText {
    /// "3 to pass alice".
    static func passLine(_ state: LiveRankState) -> String? {
        guard let gap = state.gapToPass, let above = state.above else { return nil }
        return "\(gap) to pass \(above.login)"
    }

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
