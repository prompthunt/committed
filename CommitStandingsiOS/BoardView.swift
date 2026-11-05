import SwiftUI

/// The Board tab: your summary, people-sync status, and the ranked leaderboard for the
/// selected Window. The summary and the leaderboard are separate views so an open iPhone Duo
/// can show them side by side (#46); closed, the summary is the list's first section.
struct BoardView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let board = Board(store: app.store, refresh: app.refresh)
        NavigationStack {
            List {
                Section {
                    if let summary = board.summary {
                        BoardSummaryView(summary: summary)
                    }
                    RosterStatusView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowSeparator(.hidden)
                LeaderboardSection(board: board)
            }
            .listStyle(.plain)
            .overlay { BoardEmptyState(board: board) }
            .refreshable {
                // Pull-to-refresh is the manual Refresh: people plus Contributions.
                await app.refresh.refreshAll(reason: .manual)
            }
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
