import ActivityKit
import SwiftUI
import WidgetKit

/// Live rank: your current rank in the Dynamic Island and on the Lock Screen (spec #39).
/// Every presentation uses tabular numerals and no fixed widths, so it reads in iPhone Duo's
/// vertical Dynamic Island as well as the standard horizontal one. Placeholders, never zero,
/// stand in for numbers that haven't loaded. Past its stale date (20 minutes after the data) the
/// numbers dim and the refresh age shows. Tapping opens the board on Live rank's Window.
struct LiveRankLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveRankAttributes.self) { context in
            LiveRankLockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(nil)
                .widgetURL(context.state.boardURL)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveRankBadge(state: state, isStale: stale, size: .expanded)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveRankCount(state: state, isStale: stale, showsLabel: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        LiveRankNeighbors(state: state, isStale: stale)
                        LiveRankFooter(state: state, isStale: stale, alwaysShowsAge: false)
                    }
                }
            } compactLeading: {
                LiveRankBadge(state: state, isStale: stale, size: .compact)
            } compactTrailing: {
                LiveRankCount(state: state, isStale: stale, showsLabel: false)
            } minimal: {
                LiveRankBadge(state: state, isStale: stale, size: .minimal)
            }
            .keylineTint(LiveRankStyle.trophy)
            .widgetURL(state.boardURL)
        }
    }
}

enum LiveRankStyle {
    static let trophy = Color.yellow
    static let contributions = Color.green
    /// Stale numbers dim instead of disappearing, so an old rank never reads as current.
    static func numberOpacity(stale: Bool) -> Double { stale ? 0.45 : 1 }
}

extension LiveRankState {
    /// "#2", or nil with no rank (no data yet, or nobody else on your board).
    var rankText: String? { rank.map { "#\($0)" } }

    /// Your count, or a dash (never zero) until it loads.
    var contributionsText: String { contributions.map(String.init) ?? "–" }

    var windowTitle: String { contributionWindow?.shortTitle ?? "Today" }

    /// One line on what it takes to move: "3 to pass alice", "Ahead of bob by 2", and so on.
    var standingLine: String {
        if contributions == nil { return "Waiting for your Contributions" }
        if competitorCount <= 1 { return "No one else on your board yet" }
        if let gap = gapToPass, let above { return "\(gap) to pass \(above.login)" }
        if rank == 1, let below, let contributions {
            let lead = contributions - below.contributions
            return lead > 0 ? "Ahead of \(below.login) by \(lead)" : "Tied with \(below.login)"
        }
        return "In the lead"
    }

    var accessibilitySummary: String {
        var parts: [String] = []
        if let rank { parts.append("Rank \(rank) of \(competitorCount) \(contributionWindow?.accessibilityDescription ?? "today")") }
        parts.append(contributions.map { "\($0) contributions" } ?? "Contributions not loaded")
        parts.append(standingLine)
        if movementToday > 0 { parts.append("up \(movementToday) today") }
        if movementToday < 0 { parts.append("down \(-movementToday) today") }
        return parts.joined(separator: ", ")
    }
}

/// The rank with the trophy glyph; just the glyph when there's no rank to show.
struct LiveRankBadge: View {
    enum Size { case minimal, compact, expanded }

    let state: LiveRankState
    let isStale: Bool
    let size: Size

    var body: some View {
        HStack(spacing: size == .expanded ? 4 : 2) {
            if size != .minimal || state.rankText == nil {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(LiveRankStyle.trophy)
                    .imageScale(size == .expanded ? .medium : .small)
            }
            if let rank = state.rankText {
                Text(rank)
                    .font(size == .expanded ? .title2.weight(.bold) : .body.weight(.semibold))
                    .monospacedDigit()
                    .opacity(LiveRankStyle.numberOpacity(stale: isStale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if size == .expanded, state.movementToday != 0 {
                LiveRankMovement(movement: state.movementToday)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.rank.map { "Rank \($0)" } ?? "Live rank")
    }
}

/// Your Contributions next to a green square, like the contribution graph.
struct LiveRankCount: View {
    let state: LiveRankState
    let isStale: Bool
    let showsLabel: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: "square.fill")
                    .foregroundStyle(LiveRankStyle.contributions)
                    .imageScale(.small)
                Text(state.contributionsText)
                    .font(showsLabel ? .title2.weight(.bold) : .body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(LiveRankStyle.numberOpacity(stale: isStale))
            }
            if showsLabel {
                Text(state.windowTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.contributions.map { "\($0) contributions" } ?? "Contributions not loaded")
    }
}

struct LiveRankMovement: View {
    let movement: Int

    var body: some View {
        HStack(spacing: 1) {
            Image(systemName: movement > 0 ? "chevron.up" : "chevron.down")
            Text("\(abs(movement))").monospacedDigit()
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(movement > 0 ? .green : .red)
        .accessibilityLabel(movement > 0 ? "Up \(movement) today" : "Down \(-movement) today")
    }
}

/// You between the people directly above and below you.
struct LiveRankNeighbors: View {
    let state: LiveRankState
    let isStale: Bool

    var body: some View {
        if state.rank != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let above = state.above, let rank = state.rank {
                    row(rank: rank - 1, name: above.login, count: String(above.contributions), isYou: false)
                }
                row(rank: state.rank, name: "you", count: state.contributionsText, isYou: true)
                if let below = state.below, let rank = state.rank {
                    row(rank: rank + 1, name: below.login, count: String(below.contributions), isYou: false)
                }
            }
        }
    }

    private func row(rank: Int?, name: String, count: String, isYou: Bool) -> some View {
        HStack(spacing: 8) {
            Text(rank.map { "\($0)" } ?? "–")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(count)
                .monospacedDigit()
                .opacity(LiveRankStyle.numberOpacity(stale: isStale))
        }
        .font(isYou ? .subheadline.weight(.semibold) : .subheadline)
        .foregroundStyle(isYou ? .primary : .secondary)
    }
}

/// What it takes to move up, and how old the numbers are.
struct LiveRankFooter: View {
    let state: LiveRankState
    let isStale: Bool
    /// The Lock Screen always shows the age; the Dynamic Island only once it's stale.
    let alwaysShowsAge: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                standing
                Spacer(minLength: 8)
                age
            }
            VStack(alignment: .leading, spacing: 2) {
                standing
                age
            }
        }
        .font(.footnote)
    }

    private var standing: some View {
        Text(state.standingLine)
            .fontWeight(.medium)
            .lineLimit(2)
    }

    @ViewBuilder
    private var age: some View {
        if alwaysShowsAge || isStale {
            HStack(spacing: 3) {
                if isStale { Image(systemName: "clock.badge.exclamationmark") }
                Text("Updated \(Text(.currentDate, format: .reference(to: state.updatedDate, allowedFields: [.day, .hour, .minute], maxFieldCount: 1, thresholdField: .minute)))")
            }
            .foregroundStyle(isStale ? .orange : .secondary)
            .lineLimit(2)
        }
    }
}

/// The Lock Screen card: the Dynamic Island's information, plus the Window and refresh age.
struct LiveRankLockScreenView: View {
    let state: LiveRankState
    let isStale: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text("Live rank · \(state.windowTitle)")
                } icon: {
                    Image(systemName: "trophy.fill").foregroundStyle(LiveRankStyle.trophy)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let rank = state.rankText {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(rank)
                            .font(.largeTitle.weight(.bold))
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("of \(state.competitorCount)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .monospacedDigit()
                    .opacity(LiveRankStyle.numberOpacity(stale: isStale))
                    if state.movementToday != 0 { LiveRankMovement(movement: state.movementToday) }
                    Spacer(minLength: 0)
                }
                // With no rank, your Contributions lead the card instead of sitting alone on the right.
                LiveRankCount(state: state, isStale: isStale, showsLabel: !dynamicTypeSize.isAccessibilitySize)
                if state.rankText == nil { Spacer(minLength: 0) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // At accessibility sizes the neighbor rows give way so the rank and gap stay legible.
            if !dynamicTypeSize.isAccessibilitySize {
                LiveRankNeighbors(state: state, isStale: isStale)
            }
            LiveRankFooter(state: state, isStale: isStale, alwaysShowsAge: true)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.accessibilitySummary)
    }
}

// MARK: - Previews

extension LiveRankState {
    fileprivate static let preview = LiveRankState(
        window: "daily", rank: 2, competitorCount: 7, contributions: 12,
        above: .init(login: "torvalds", contributions: 14), below: .init(login: "gaearon", contributions: 9),
        movementToday: 1, updatedAt: Int(Date.now.timeIntervalSince1970) - 240
    )
    fileprivate static let leading = LiveRankState(
        window: "weekly", rank: 1, competitorCount: 7, contributions: 88,
        above: nil, below: .init(login: "torvalds", contributions: 80),
        movementToday: 0, updatedAt: Int(Date.now.timeIntervalSince1970) - 60
    )
    fileprivate static let noRivals = LiveRankState(
        window: "daily", rank: nil, competitorCount: 1, contributions: 4,
        above: nil, below: nil, movementToday: 0, updatedAt: Int(Date.now.timeIntervalSince1970)
    )
    fileprivate static let noData = LiveRankState(
        window: "daily", rank: nil, competitorCount: 5, contributions: nil,
        above: nil, below: nil, movementToday: 0, updatedAt: Int(Date.now.timeIntervalSince1970)
    )
}

#Preview("Lock Screen", as: .content, using: LiveRankAttributes(selfLogin: "octocat")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.preview
    LiveRankState.leading
    LiveRankState.noRivals
    LiveRankState.noData
}

#Preview("Compact", as: .dynamicIsland(.compact), using: LiveRankAttributes(selfLogin: "octocat")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.preview
    LiveRankState.noRivals
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: LiveRankAttributes(selfLogin: "octocat")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.preview
    LiveRankState.leading
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: LiveRankAttributes(selfLogin: "octocat")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.preview
    LiveRankState.noRivals
}
