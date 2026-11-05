import SwiftUI

/// The Board tab: a split arrangement with the ranked leaderboard as the primary pane and your
/// summary (standing plus people-sync status) as the secondary. Where the arrangement can't
/// split (the Duo closed, a regular iPhone, Split View) only the leaderboard shows, with the
/// summary as its first section. Where it can (the Duo open in regular width, or folded with the
/// fold dividing the panes), the two share the screen evenly: side by side, or top and bottom
/// when the screen is taller than wide (tabletop). One `List` serves every pose, so opening and
/// closing keep the scroll position; the tab and Window live in `AppModel` and `StandingsStore`.
struct BoardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var placement = SummaryPlacement()

    private var splitAxes: Axis.Set {
        horizontalSizeClass == .compact ? .horizontal : [.horizontal, .vertical]
    }

    var body: some View {
        let board = Board(store: app.store, refresh: app.refresh)
        NavigationStack {
            ArrangementView {
                LeaderboardList(board: board, showsSummary: placement.isInLeaderboard)
                    .onGeometryChange(for: CGSize.self, of: \.size) { placement.leaderboardResized(to: $0) }
            } secondary: {
                BoardSummaryPane(board: board)
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { placement.arrangementResized(to: $0) }
            // Compact width (the Duo closed, a regular iPhone, Split View) is a phone-shaped
            // screen: splitting it would halve the leaderboard, so only side by side is allowed
            // and a tall compact screen shows the leaderboard alone. Regular width may split
            // either way, which lets a tabletop fold divide the panes top and bottom.
            .arrangementViewStyle(.split.axes(splitAxes))
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WindowPicker()
                }
            }
        }
    }
}

/// The primary pane. Carries the summary as its first section when the arrangement shows it
/// alone, and keeps your place when the panes change around it.
private struct LeaderboardList: View {
    let board: Board
    let showsSummary: Bool
    @Environment(AppModel.self) private var app
    @State private var anchor = LeaderboardScrollAnchor<UUID>()

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if showsSummary {
                    Section {
                        BoardSummaryContent(board: board)
                    }
                    .listRowSeparator(.hidden)
                }
                LeaderboardSection(
                    board: board,
                    rowAppeared: { anchor.rowAppeared($0) },
                    rowDisappeared: { anchor.rowDisappeared($0) }
                )
            }
            .listStyle(.plain)
            // On the leaderboard pane, not the whole arrangement, so it never sits in the fold.
            .overlay { BoardEmptyState(board: board) }
            .refreshable {
                // Pull-to-refresh is the manual Refresh: people plus Contributions.
                await app.refresh.refreshAll(reason: .manual)
            }
            .onChange(of: showsSummary) {
                // The summary just moved in or out of the list (opening or closing the
                // device); put the row you were looking at back at the top.
                if let id = anchor.rowToRestore(in: board.rows.map(\.id)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }
}

/// The secondary pane: your summary and people-sync status, scrollable so it holds at
/// accessibility text sizes and in a short tabletop half.
private struct BoardSummaryPane: View {
    let board: Board

    var body: some View {
        ScrollView {
            BoardSummaryContent(board: board)
                .scenePadding()
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Your summary card and the people-sync line, shared by both panes.
private struct BoardSummaryContent: View {
    let board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = board.summary {
                BoardSummaryView(summary: summary)
            }
            RosterStatusView()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Today / 7 days / 30 days. Too wide for a vertical bar, so it stays horizontal in the
/// navigation bar.
private struct WindowPicker: View {
    @Environment(StandingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Picker("Window", selection: $store.selectedWindow) {
            ForEach(ContributionWindow.allCases) { window in
                Text(window.shortTitle).tag(window)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

/// The ranked `StandingRow`s (the one board row shared with the Mac) plus the
/// private-contributions tip.
struct LeaderboardSection: View {
    let board: Board
    var rowAppeared: (UUID) -> Void = { _ in }
    var rowDisappeared: (UUID) -> Void = { _ in }

    var body: some View {
        if board.rows.count > 1 {
            Section {
                ForEach(board.rows) { row in
                    StandingRow(
                        rank: row.rank,
                        competitor: row.competitor,
                        standing: row.standing,
                        window: board.window,
                        maxContributions: board.maxContributions,
                        rankDelta: row.rankDelta
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    .listRowSeparator(.hidden)
                    .onAppear { rowAppeared(row.id) }
                    .onDisappear { rowDisappeared(row.id) }
                }
            } header: {
                Text("Tracking \(board.rows.count) people")
            }
        } else if board.summary != nil {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your circle starts here")
                        .font(.headline)
                    Text("Follow people on GitHub or join an organization to see them on your board automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            }
        }
        if board.summary != nil {
            Section {
                PrivateContributionsTip()
                    .listRowSeparator(.hidden)
            }
        }
    }
}

/// Before people sync there's nothing to rank yet; say so instead of an empty list.
private struct BoardEmptyState: View {
    let board: Board
    @Environment(GitHubRoster.self) private var roster

    var body: some View {
        if board.summary == nil, roster.errorMessage == nil {
            ContentUnavailableView {
                Label("Loading your people", systemImage: "person.2")
            } description: {
                Text("Committed is syncing the people you follow and your organization members from GitHub.")
            } actions: {
                ProgressView()
            }
        }
    }
}
