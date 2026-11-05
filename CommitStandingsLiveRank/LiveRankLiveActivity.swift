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
            .keylineTint(.yellow)
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
        .font(style == .expanded ? .title3 : .body)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveRankText.rankAccessibility(state))
    }

    @ViewBuilder private var trophy: some View {
        if style != .minimal || state.rank == nil {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var rankText: some View {
        if let rank = state.rank {
            Text("#\(rank)")
                .fontWeight(.semibold)
                .monospacedDigit()
        } else if state.competitorCount > 1 {
            // Rivals but no count of yours yet.
            Text(placeholder)
        }
    }

    @ViewBuilder private var extras: some View {
        if style == .expanded, state.rank != nil {
            Text("of \(state.competitorCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if state.movementToday != 0 {
                // Today's movement since the morning, like the board's chevrons.
                Label("\(abs(state.movementToday))",
                      systemImage: state.movementToday > 0 ? "chevron.up" : "chevron.down")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.movementToday > 0 ? .green : .red)
                    .monospacedDigit()
            }
        }
    }
}

/// Your Contributions for the Window.
struct LiveRankCountLabel: View {
    let state: LiveRankState
    let showsUnit: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(state.contributions.map { "\($0)" } ?? placeholder)
                .fontWeight(.semibold)
                .monospacedDigit()
            if showsUnit {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
        }
        .font(showsUnit ? .title3 : .body)
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
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.yellow)
                    .monospacedDigit()
                    .lineLimit(2)
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
        .font(.subheadline)
        .fontWeight(isYou ? .semibold : .regular)
        .foregroundStyle(isYou ? .primary : .secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveRankText.rowAccessibility(rank: rank, login: login, contributions: contributions))
    }

    private var rankText: some View {
        Text(rank.map { "#\($0)" } ?? placeholder).monospacedDigit()
    }

    private var name: some View {
        Text(login).lineLimit(1).truncationMode(.middle)
    }

    private var count: some View {
        Text(contributions.map { "\($0)" } ?? placeholder).monospacedDigit()
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
        .foregroundStyle(isStale ? .orange : .secondary)
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
            HStack(alignment: .firstTextBaseline) {
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
        .activityBackgroundTint(Color.black.opacity(0.6))
        .activitySystemActionForegroundColor(.yellow)
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
