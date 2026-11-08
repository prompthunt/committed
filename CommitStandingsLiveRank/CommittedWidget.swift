import SwiftUI
import WidgetKit

/// Committed on the Home Screen and the Lock Screen, and (the small size) in CarPlay and StandBy.
///
/// Every size shows Live rank's Window from `WidgetSnapshot`, which the app writes after each
/// refresh and then reloads these widgets. Nothing is fetched here. The timeline holds the snapshot
/// as written, plus one more entry at its stale date (20 minutes after the data) that steps the
/// colors down and adds the clock, as Live rank does. Without a snapshot (not connected yet), the
/// widget asks you to open Committed; the placeholder and gallery use a sample board.
struct CommittedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: CommittedWidgetProvider()) { entry in
            CommittedWidgetView(entry: entry)
                .environment(\.liveRankIsStale, entry.isStale)
                .widgetURL(entry.snapshot?.state.boardURL ?? DeepLink.board(window: nil).url)
        }
        .configurationDisplayName("Committed")
        .description("Your place on the board, and how many Contributions to pass the person ahead.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}

// MARK: - Timeline

struct CommittedWidgetEntry: TimelineEntry {
    let date: Date
    /// nil when the app hasn't written one: not connected yet, or disconnected.
    let snapshot: WidgetSnapshot?
    let isStale: Bool

    init(date: Date, snapshot: WidgetSnapshot?) {
        self.date = date
        self.snapshot = snapshot
        isStale = snapshot.map { $0.state.staleDate <= date } ?? false
    }
}

struct CommittedWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CommittedWidgetEntry {
        CommittedWidgetEntry(date: .now, snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (CommittedWidgetEntry) -> Void) {
        let saved = WidgetSnapshot.load()
        // The gallery shows your own board when there is one, the sample otherwise.
        completion(CommittedWidgetEntry(date: .now, snapshot: context.isPreview ? saved ?? .sample() : saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CommittedWidgetEntry>) -> Void) {
        let now = Date.now
        let saved = WidgetSnapshot.load()
        var entries = [CommittedWidgetEntry(date: now, snapshot: saved)]
        if let saved, saved.state.staleDate > now {
            entries.append(CommittedWidgetEntry(date: saved.state.staleDate, snapshot: saved))
        }
        // The app reloads after every refresh; there's nothing to fetch from here.
        completion(Timeline(entries: entries, policy: .never))
    }
}

// MARK: - Views

struct CommittedWidgetView: View {
    let entry: CommittedWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            CommittedWidgetInline(snapshot: entry.snapshot)
        case .accessoryCircular:
            CommittedWidgetCircular(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            CommittedWidgetRectangular(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        default:
            Group {
                if let snapshot = entry.snapshot {
                    switch family {
                    case .systemMedium: CommittedWidgetMedium(snapshot: snapshot)
                    case .systemLarge: CommittedWidgetLarge(snapshot: snapshot)
                    default: CommittedWidgetSmall(snapshot: snapshot)
                    }
                } else {
                    CommittedWidgetConnect()
                }
            }
            .environment(\.colorScheme, .dark)
            .containerBackground(for: .widget) { Color.ink }
        }
    }
}

/// The trophy and the Window ("TODAY"), heading every system size.
private struct WidgetHeader: View {
    let state: LiveRankState
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        HStack(spacing: 6) {
            TrophyMark(size: 16, color: isStale ? .limeDeep : .lime)
            if let window = state.contributionWindow {
                Text(window.shortTitle)
                    .eyebrow()
                    .foregroundStyle(isStale ? Color.warning : Color.soft)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.contributionWindow.map { "Committed, \($0.accessibilityDescription)" } ?? "Committed")
    }
}

/// The gap to pass, what it's waiting for, or (stale) how old the numbers are: one line.
private struct WidgetStatusLine: View {
    let state: LiveRankState
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        Group {
            if isStale {
                HStack(spacing: 3) {
                    Image(systemName: "clock.badge.exclamationmark").accessibilityHidden(true)
                    CommittedWidgetText.age(state)
                }
                .foregroundStyle(Color.warning)
                .accessibilityElement(children: .combine)
            } else if state.hasLadder {
                Text(state.passLine ?? "Leading the board")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.lime)
            } else if let line = state.emptyStateLine {
                Text(line).foregroundStyle(Color.soft)
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Small (also CarPlay and StandBy): the Window, your rank big, your count, then the gap to pass.
/// Read at a glance from the driver's seat, so no rows.
struct CommittedWidgetSmall: View {
    let snapshot: WidgetSnapshot
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        let state = snapshot.state
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(state: state)
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
                ContributionSquare(level: state.contributions.map { $0 > 0 ? (isStale ? 3 : 4) : 0 } ?? 0,
                                   size: ranked ? 12 : 18)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LiveRankText.countAccessibility(state))
            WidgetStatusLine(state: state)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Medium: the header with the gap to pass, then the person above you, you, and the person below
/// in the board's own rows, as Live rank's expanded island shows them.
struct CommittedWidgetMedium: View {
    let snapshot: WidgetSnapshot
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        let state = snapshot.state
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WidgetHeader(state: state)
                Spacer(minLength: 8)
                // Without rows the body already says what it's waiting for.
                if state.hasLadder || isStale {
                    WidgetStatusLine(state: state)
                }
            }
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

/// Large: the top of the board in its own rows, then you below a rule when you're further down.
struct CommittedWidgetLarge: View {
    let snapshot: WidgetSnapshot
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        let state = snapshot.state
        let window = state.contributionWindow ?? .daily
        let shown = snapshot.top + (snapshot.selfIsInTop ? [] : snapshot.selfRow.map { [$0] } ?? [])
        let busiest = shown.compactMap(\.contributions).max() ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetHeader(state: state)
                Spacer(minLength: 8)
                WidgetStatusLine(state: state)
            }
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

/// One board row through the shared `StandingRow` (never forked).
private struct WidgetBoardRow: View {
    let row: WidgetSnapshot.Row
    let window: ContributionWindow
    let updated: Date
    let busiest: Int

    var body: some View {
        StandingRow(
            rank: row.rank,
            competitor: Competitor(username: row.login, isSelf: row.isSelf),
            standing: row.contributions.map {
                Standing(username: row.login, contributions: $0, window: window, lastUpdated: updated, state: .loaded)
            },
            window: window,
            maxContributions: busiest,
            rankDelta: row.movement
        )
    }
}

/// Not connected: what to do, in place of a board.
struct CommittedWidgetConnect: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrophyMark(size: 22)
            Spacer(minLength: 0)
            Text("Open Committed and connect GitHub to see your rank.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Lock Screen

/// "#3 · 42 today" over the gap to pass. Rendered in the Lock Screen's tint, so no color carries
/// meaning.
struct CommittedWidgetRectangular: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let state = snapshot?.state {
                Text(CommittedWidgetText.headline(state))
                    .font(.headline)
                    .widgetAccentable()
                if isStale {
                    Label { CommittedWidgetText.age(state) } icon: {
                        Image(systemName: "clock.badge.exclamationmark")
                    }
                    .font(.caption)
                } else if let line = state.passLine ?? state.emptyStateLine {
                    Text(line).font(.caption)
                }
            } else {
                Text("Committed").font(.headline).widgetAccentable()
                Text("Connect GitHub to see your rank").font(.caption)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line above the clock: your rank and count, or the gap to pass.
struct CommittedWidgetInline: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let state = snapshot?.state {
            Label(CommittedWidgetText.inline(state), systemImage: "trophy.fill")
        } else {
            Label("Committed", systemImage: "trophy.fill")
        }
    }
}

/// The trophy over your rank.
struct CommittedWidgetCircular: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "trophy.fill")
                .font(.caption)
                .widgetAccentable()
            Text(snapshot?.state.rank.map { "#\($0)" } ?? "–")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.map { LiveRankText.rankAccessibility($0.state) } ?? "Committed")
    }
}

enum CommittedWidgetText {
    /// "45 minutes ago", counting on without a reload, as Live rank's footer does.
    static func age(_ state: LiveRankState) -> Text {
        Text(.currentDate, format: .reference(to: state.updatedDate, allowedFields: [.minute, .hour, .day], maxFieldCount: 1))
    }

    /// "#3 · 42 today", or "42 today" without a rank, or the Window alone without a count.
    static func headline(_ state: LiveRankState) -> String {
        let window = state.contributionWindow?.shortTitle.lowercased() ?? ""
        let count = state.contributions.map { "\($0) \(window)" }
        switch (state.rank, count) {
        case let (rank?, count?): return "#\(rank) · \(count)"
        case let (nil, count?): return count
        default: return state.contributionWindow?.shortTitle ?? "Committed"
        }
    }

    /// The gap to pass when there is one, otherwise the headline.
    static func inline(_ state: LiveRankState) -> String {
        if let rank = state.rank, let line = state.passLine { return "#\(rank) · \(line)" }
        return headline(state)
    }
}
