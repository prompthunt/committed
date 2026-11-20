import SwiftUI

// These four card layouts are shared by the iPhone widgets and the board image exports on
// iPhone and Mac. WidgetKit wraps them in its timeline configurations.
//
// Every system size heads itself as Live rank does: the trophy and the Window ("Today") at 16 pt,
// and how long ago the numbers were updated ("13 min, 36 sec") counting up at 12 pt on the right,
// or, where a small widget has no room beside the Window, on its own line.

/// Small (also CarPlay and StandBy): the Window, your rank big, your count and streak, then the
/// age. Read at a glance from the driver's seat, so no rows.
struct CommittedWidgetSmall: View {
    let snapshot: WidgetSnapshot
    var usesContributionGrid = false
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        let state = snapshot.state
        VStack(alignment: .leading, spacing: 2) {
            LiveRankWindowLabel(state: state, accessibilityName: "Committed")
            Spacer(minLength: 4)
            // With nobody else on the board there's no rank: your count takes its place.
            let ranked = state.rank != nil || state.competitorCount > 1
            if ranked {
                Text(state.rank.map { "#\($0)" } ?? "–")
                    .font(CommittedType.display(44, relativeTo: .largeTitle))
                    .displayTracking(44)
                    .foregroundStyle(isStale ? Color.muted : .white)
                    .accessibilityLabel(LiveRankText.rankAccessibility(state))
            }
            HStack(alignment: .center, spacing: 5) {
                Text(state.contributions.map { "\($0)" } ?? "–")
                    .font(CommittedType.display(ranked ? 22 : 44, relativeTo: ranked ? .title2 : .largeTitle))
                    .displayTracking(ranked ? 0 : 44)
                    .foregroundStyle(isStale ? Color.limeDeep : Color.lime)
                let level = state.contributions.map { $0 > 0 ? (isStale ? 3 : 4) : 0 } ?? 0
                if usesContributionGrid {
                    ContributionGrid(size: ranked ? 12 : 18, color: level == 0 ? .muted : Color.contributionSquares[level])
                } else {
                    ContributionSquare(level: level, size: ranked ? 12 : 18)
                }
                // Your streak on the count's line, so the card keeps its four lines. Only beside
                // your count (`state.streak` is nil without it), from 2 days.
                if StreakLabel.number(state.streak) != nil {
                    Spacer(minLength: 4)
                    StreakBadge(streak: state.streak, markSize: ranked ? 14 : 16, relativeTo: .subheadline,
                                markColor: isStale ? Color.rowGlyphs[1] : .limeDeep)
                        .font(CommittedType.numeral(ranked ? 15 : 17, relativeTo: .subheadline))
                        .foregroundStyle(isStale ? Color.muted : Color.soft)
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LiveRankText.countAccessibility(state, streak: true))
            WidgetStatusLine(state: state)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// A small widget's last line: the age, or what the board is waiting for when there's no count.
private struct WidgetStatusLine: View {
    let state: LiveRankState

    var body: some View {
        if state.contributions == nil || state.competitorCount <= 1, let line = state.emptyStateLine {
            Text(line)
                .font(CommittedType.widgetText(.footnote, size: 13))
                .foregroundStyle(Color.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            UpdateAge(date: state.updatedDate)
        }
    }
}

/// Medium: the header, then the person above you, you, and the person below in the board's own
/// rows, as Live rank's expanded island shows them.
struct CommittedWidgetMedium: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let state = snapshot.state
        VStack(alignment: .leading, spacing: 6) {
            LiveRankHeader(state: state, accessibilityName: "Committed")
            Spacer(minLength: 0)
            if state.hasLadder {
                LiveRankRows(state: state, selfLogin: snapshot.selfLogin)
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
            Spacer(minLength: 0)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Large: the header, then the top of the board in its own rows, then you below a rule when
/// you're further down.
struct CommittedWidgetLarge: View {
    let snapshot: WidgetSnapshot
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        let state = snapshot.state
        let window = state.contributionWindow ?? .daily
        let shown = snapshot.top + (snapshot.selfIsInTop ? [] : snapshot.selfRow.map { [$0] } ?? [])
        let busiest = shown.compactMap(\.contributions).max() ?? 0
        VStack(alignment: .leading, spacing: 8) {
            LiveRankHeader(state: state, accessibilityName: "Committed")
            VStack(spacing: 8) {
                ForEach(snapshot.top, id: \.rank) { row in
                    WidgetBoardRow(row: row, window: window, updated: state.updatedDate, busiest: busiest)
                }
                if !snapshot.selfIsInTop, let me = snapshot.selfRow {
                    Divider().overlay(Color.muted.opacity(0.4)).padding(.vertical, 2)
                    WidgetBoardRow(row: me, window: window, updated: state.updatedDate, busiest: busiest)
                }
            }
            .padding(.horizontal, -10)
            .foregroundStyle(isStale ? Color.soft : Color.white)
            .environment(\.standingRowStyle, .liveRank(stale: isStale))
            .environment(\.avatarFallbackStyle, .committed)
            .environment(\.loadsGitHubAvatars, false)
            Spacer(minLength: 0)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

/// Small Board: the Window, four of the board's rows, then the age.
///
/// In StandBy the system drops the background and scales the small widget up to fill its slot; on
/// iPhone Duo's right half that's about three times its Home Screen size, beside widgets in smaller
/// slots, where a 16 pt heading and 12 pt age grow to the size of the rows. So there (`standBy`) the
/// board leads: no heading, the rows share the height, and the Window and the age share one 10 pt
/// line underneath.
struct CommittedWidgetBoardSmall: View {
    let snapshot: WidgetSnapshot
    var standBy = false
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        let state = snapshot.state
        if standBy {
            VStack(spacing: 6) {
                board(state)
                footer(state)
            }
            .dynamicTypeSize(...DynamicTypeSize.large)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                LiveRankWindowLabel(state: state, accessibilityName: "Committed")
                board(state)
                Spacer(minLength: 0)
                UpdateAge(date: state.updatedDate)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .dynamicTypeSize(...DynamicTypeSize.large)
        }
    }

    @ViewBuilder private func board(_ state: LiveRankState) -> some View {
        let window = state.contributionWindow ?? .daily
        let rows = snapshot.boardRows()
        let busiest = (snapshot.top + rows).compactMap(\.contributions).max() ?? 0
        if rows.isEmpty {
            Spacer(minLength: 0)
            Text(state.emptyStateLine ?? "Your board is loading")
                .font(CommittedType.widgetText(.footnote, size: 13))
                .foregroundStyle(Color.soft)
                .frame(maxWidth: .infinity, alignment: standBy ? .center : .leading)
                .multilineTextAlignment(standBy ? .center : .leading)
            if standBy { Spacer(minLength: 0) }
        } else {
            VStack(spacing: standBy ? 0 : 2) {
                // No streaks: beside whole counts, the small widget's rows have no room for them.
                ForEach(rows, id: \.rank) { row in
                    WidgetBoardRow(row: row, window: window, updated: state.updatedDate, busiest: busiest,
                                   showsStreak: false)
                        .frame(maxHeight: standBy ? .infinity : nil)
                }
            }
            // The rows' own padding reaches into the margins, so names keep their width.
            .padding(.horizontal, -6)
            .foregroundStyle(isStale ? Color.soft : Color.white)
            .environment(\.standingRowStyle, .widgetBoard(stale: isStale))
            .environment(\.avatarFallbackStyle, .committed)
            .environment(\.loadsGitHubAvatars, false)
        }
    }

    /// StandBy's one small line: the trophy and the Window on the left, the age on the right.
    private func footer(_ state: LiveRankState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            LiveRankWindowLabel(state: state, accessibilityName: "Committed", size: 10)
            Spacer(minLength: 0)
            UpdateAge(date: state.updatedDate, size: 10)
        }
    }
}

extension StandingRowStyle {
    /// Live rank's row, cut to a small widget's width: smaller type and avatar, no count column
    /// minimum, no squares glyph, and no "you" badge (your row's highlight marks you). Names
    /// truncate first, as on every row.
    static func widgetBoard(stale: Bool) -> StandingRowStyle {
        var style = StandingRowStyle.liveRank(stale: stale)
        style.rankFont = CommittedType.numeral(11, relativeTo: .caption2)
        style.rankWidthScale = 0.85
        style.nameFont = CommittedType.widgetText(.caption, size: 12, weight: .medium)
        style.selfNameFont = CommittedType.widgetText(.caption, size: 12, weight: .bold)
        style.countFont = CommittedType.numeral(13, relativeTo: .caption)
        style.selfCountFont = CommittedType.display(13, relativeTo: .caption)
        style.avatarSize = 16
        style.spacing = 5
        style.horizontalPadding = 6
        style.verticalPadding = 3
        style.countMinWidth = 0
        style.showsSelfBadge = false
        style.squares = .hidden
        style.cornerRadius = 8
        return style
    }
}

/// One board row through the shared `StandingRow` (never forked), with its streak unless the row
/// is too narrow for one.
private struct WidgetBoardRow: View {
    let row: WidgetSnapshot.Row
    let window: ContributionWindow
    let updated: Date
    let busiest: Int
    var showsStreak = true

    var body: some View {
        StandingRow(
            rank: row.rank,
            competitor: Competitor(username: row.login, isSelf: row.isSelf),
            standing: row.contributions.map {
                Standing(username: row.login, contributions: $0, window: window, lastUpdated: updated, state: .loaded)
            },
            window: window,
            maxContributions: busiest,
            rankDelta: row.movement,
            streak: showsStreak ? row.streak : nil
        )
    }
}
