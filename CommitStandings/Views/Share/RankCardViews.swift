import SwiftUI

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
    /// 16 pt everywhere but the StandBy board's footer line.
    var size: CGFloat = 16
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        HStack(spacing: size * 6 / 16) {
            TrophyMark(size: size + 1, color: isStale ? .limeDeep : .lime)
            if let window = state.contributionWindow {
                Text(window.shortTitle)
                    .font(.system(size: size))
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
    /// 12 pt everywhere but the StandBy board's footer line.
    var size: CGFloat = 12
    @Environment(\.showsUpdateAge) private var showsUpdateAge

    var body: some View {
        if showsUpdateAge {
            Text(date, style: .relative)
                .font(.system(size: size))
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

extension EnvironmentValues {
    /// Live rank's content is past its stale date.
    @Entry var liveRankIsStale = false
    /// Whether `UpdateAge` shows. Share board's images turn it off.
    @Entry var showsUpdateAge = true
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
