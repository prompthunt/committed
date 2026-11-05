import SwiftUI

/// The Board tab: your summary, then everyone ranked with the shared `StandingRow`. The Window
/// switch sits in the navigation bar; pull to refresh reloads people and Contributions.
///
/// Two panes in a split arrangement: the leaderboard is primary, so it's the pane that survives
/// when there's room for only one, and your summary is secondary. Side by side they divide the
/// width evenly (at the fold on iPhone Duo); otherwise the summary heads the leaderboard.
struct BoardView: View {
    @Environment(AppModel.self) private var model
    @Environment(StandingsStore.self) private var store
    /// Where the two panes are, as they last reported. Lives above the arrangement so it survives
    /// the panes being rebuilt when the device opens, closes, or folds.
    @State private var arrangementFrame: CGRect?
    @State private var leaderboardFrame: CGRect?
    @State private var summaryFrame: CGRect?

    var body: some View {
        NavigationStack {
            ArrangementView {
                BoardLeaderboard(
                    summaryPlacement: BoardArrangement.summaryPlacement(
                        arrangement: arrangementFrame, leaderboard: leaderboardFrame, summary: summaryFrame
                    )
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.arrangementSpace)) } action: {
                    leaderboardFrame = $0
                }
            } secondary: {
                BoardSummaryPane()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.arrangementSpace)) } action: {
                        summaryFrame = $0
                    }
            }
            .coordinateSpace(.named(Self.arrangementSpace))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .local) } action: { arrangementFrame = $0 }
            .arrangementViewStyle(.split.axes(.horizontal))
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ContributionWindowPicker()
                        .fixedSize()
                }
            }
            .refreshable { await model.pullToRefresh() }
        }
        .onChange(of: store.selectedWindow) {
            Task { await model.windowDidChange() }
        }
    }

    private nonisolated static let arrangementSpace = "BoardArrangement"
}

/// The ranked list, headed by your summary whenever the summary has no pane of its own.
struct BoardLeaderboard: View {
    @Environment(AppModel.self) private var model
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    let summaryPlacement: BoardArrangement.SummaryPlacement

    var body: some View {
        let window = store.selectedWindow
        let standings = store.standings(for: window)
        let entries = Ranking.order(competitors: store.visibleCompetitors, standings: standings, window: window)
        let maxContributions = entries.compactMap { standings[$0.competitor.username] }
            .filter { $0.lastUpdated != .distantPast }
            .map(\.contributions).max() ?? 0

        List {
            if summaryPlacement == .leaderboardHeader {
                Section {
                    BoardSummaryView()
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                }
            }

            if !store.hasSelf {
                Section {
                    ContentUnavailableView {
                        Label("Loading your people", systemImage: "person.2")
                    } description: {
                        Text("You, your organization members, and the people you follow will appear here.")
                    }
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    if isInitialLoad(entries: entries) {
                        InitialLoadRow()
                            .listRowSeparator(.hidden)
                    }
                    ForEach(entries) { entry in
                        StandingRow(
                            rank: entry.rank,
                            competitor: entry.competitor,
                            standing: store.standing(for: entry.competitor.username, window: window),
                            window: window,
                            maxContributions: maxContributions,
                            rankDelta: window == .daily ? refresh.rankDelta(for: entry.competitor.username) : nil
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    }
                    if store.rivals.isEmpty {
                        SoloBoardRow()
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("\(entries.count) \(entries.count == 1 ? "person" : "people")")
                }

                Section {
                    PrivateContributionsTip()
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("Leaderboard")
    }

    /// The very first sync, before any row has numbers: one explanation instead of a board of
    /// placeholders with no context.
    private func isInitialLoad(entries: [Ranking.Entry]) -> Bool {
        guard refresh.isRefreshing else { return false }
        return !entries.contains { entry in
            guard let standing = store.standing(for: entry.competitor.username, window: store.selectedWindow)
            else { return false }
            return standing.lastUpdated != .distantPast
        }
    }
}

/// Your summary in its own pane, beside the leaderboard. It scrolls so it still fits at
/// accessibility text sizes or in a short pane.
private struct BoardSummaryPane: View {
    var body: some View {
        ScrollView {
            BoardSummaryView()
                .padding(16)
        }
        .accessibilityLabel("Your standing")
    }
}

private struct InitialLoadRow: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fetching the first set of standings").font(.subheadline.weight(.medium))
                Text("This only happens once.").font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            ProgressView()
        }
        .accessibilityElement(children: .combine)
    }
}

/// GitHub is the source of truth even when nobody else is on your board.
private struct SoloBoardRow: View {
    @Environment(AppModel.self) private var model
    @Environment(StandingsStore.self) private var store

    var body: some View {
        let everyoneHidden = store.competitors.count > 1
        VStack(spacing: 8) {
            Text(everyoneHidden ? "Your circle is hidden" : "Your circle starts here")
                .font(.headline)
            Text(everyoneHidden
                 ? "Show people again in People whenever you like."
                 : "Follow people on GitHub or join an organization to see them on your board automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open People") { model.selectedTab = .people }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
