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
    /// Read here, not in the toolbar: bar items see a capped text size, never an accessibility one.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Changes when iPhone Duo opens or closes, which the panes can't report while a pushed person
    /// view covers them.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Where the two panes are, as they last reported. Lives above the arrangement so it survives
    /// the panes being rebuilt when the device opens, closes, or folds.
    @State private var arrangementFrame: CGRect?
    @State private var leaderboardFrame: CGRect?
    @State private var summaryFrame: CGRect?
    /// The board being shared, frozen when Share is tapped so a refresh can't change the image
    /// under the carousel.
    @State private var sharing: BoardShareRequest?
    /// True while a pushed person view steps back so the panes can measure the new display.
    @State private var remeasuring = false

    var body: some View {
        NavigationStack {
            ArrangementView {
                BoardLeaderboard(summaryPlacement: summaryPlacement)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.arrangementSpace)) } action: {
                    leaderboardFrame = $0
                }
            } secondary: {
                // The person view takes your summary's pane when it has one. The frame is reported
                // from around either, so the placement doesn't change under it.
                Group {
                    if personPlacement == .secondaryPane, let person = model.shownPerson {
                        PersonPane(person: person)
                    } else {
                        BoardSummaryPane()
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.arrangementSpace)) } action: {
                    summaryFrame = $0
                }
            }
            .coordinateSpace(.named(Self.arrangementSpace))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .local) } action: { arrangementFrame = $0 }
            .arrangementViewStyle(.split.axes(.horizontal))
            // Above both panes, so it shows whether or not the summary has a pane of its own.
            .sampleBoardBanner()
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WindowSwitch(asMenu: dynamicTypeSize.isAccessibilitySize)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Share board", systemImage: "square.and.arrow.up") {
                        sharing = model.boardToShare().map(BoardShareRequest.init)
                    }
                    .disabled(!store.hasSelf)
                }
            }
            .sheet(item: $sharing) { request in
                BoardShareSheet(snapshot: request.snapshot)
            }
            .navigationDestination(item: personPush) { _ in
                PersonDestination()
            }
            .refreshable { await model.pullToRefresh() }
            #if DEBUG
            .task {
                guard ScreenshotFixture.opensShare else { return }
                try? await Task.sleep(for: .seconds(3))
                sharing = model.boardToShare().map(BoardShareRequest.init)
            }
            #endif
        }
        .onChange(of: store.selectedWindow) {
            Task { await model.windowDidChange() }
        }
        .onChange(of: horizontalSizeClass) {
            remeasure()
        }
        .onChange(of: summaryPlacement) {
            remeasuring = false
        }
    }

    /// While someone's view is pushed, the Board under it is off screen and its panes stop
    /// reporting, so opening iPhone Duo would leave the person full screen instead of in the second
    /// pane. On a size-class change, pop it without forgetting them; once the panes report (or
    /// after a moment, if nothing moved), it goes to the second pane or is pushed again.
    private func remeasure() {
        guard personPlacement == .pushed, model.shownPerson != nil else { return }
        remeasuring = true
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            remeasuring = false
        }
    }

    private var summaryPlacement: BoardArrangement.SummaryPlacement {
        BoardArrangement.summaryPlacement(arrangement: arrangementFrame, leaderboard: leaderboardFrame, summary: summaryFrame)
    }

    private var personPlacement: BoardArrangement.PersonPlacement {
        BoardArrangement.personPlacement(summary: summaryPlacement)
    }

    /// The chosen person, pushed onto the Board, wherever the Board has one pane. Opening iPhone
    /// Duo moves them to the second pane (the push pops without forgetting them); closing it pushes
    /// them again. Back, or swiping back from the edge, forgets them. Someone who leaves the board
    /// (hidden) pops it.
    private var personPush: Binding<PersonRequest?> {
        Binding(
            get: {
                guard personPlacement == .pushed, !remeasuring, let person = model.shownPerson else { return nil }
                return PersonRequest(login: person.login)
            },
            set: { request in
                if request == nil, personPlacement == .pushed, !remeasuring { model.selectedPerson = nil }
            }
        )
    }

    private nonisolated static let arrangementSpace = "BoardArrangement"
}

/// A board to share, with an identity for `.sheet(item:)`.
struct BoardShareRequest: Identifiable {
    let id = UUID()
    let snapshot: WidgetSnapshot
}

/// The person whose view is pushed, with an identity for `.navigationDestination(item:)`.
struct PersonRequest: Identifiable, Hashable {
    let login: String
    var id: String { login }
}

/// The ranked list, headed by your summary whenever the summary has no pane of its own.
struct BoardLeaderboard: View {
    @Environment(AppModel.self) private var model
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    let summaryPlacement: BoardArrangement.SummaryPlacement

    var body: some View {
        let board = RankedBoard(store)
        let window = board.window
        let entries = board.entries

        List {
            if summaryPlacement == .leaderboardHeader {
                Section {
                    BoardSummaryView()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
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
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    if isInitialLoad(entries: entries) {
                        InitialLoadRow()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(entries) { entry in
                        PersonRowButton(login: entry.competitor.username) {
                            board.row(entry, store: store, refresh: refresh)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    }
                    if store.rivals.isEmpty {
                        SoloBoardRow()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    FolioHeader("\(entries.count) \(entries.count == 1 ? "person" : "people") · \(window.shortTitle)")
                        .padding(.top, 6)
                }

                Section {
                    PrivateWorkTip()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .inkScreen()
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

/// The Window switch in the navigation bar: segments, or a menu ("Today ▾") at accessibility text
/// sizes, where the segmented control doesn't grow.
private struct WindowSwitch: View {
    @Environment(StandingsStore.self) private var store
    let asMenu: Bool

    var body: some View {
        if asMenu {
            @Bindable var store = store
            Picker("Contribution window", selection: $store.selectedWindow) {
                ForEach(ContributionWindow.allCases) { window in
                    Text(window.shortTitle).tag(window)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        } else {
            ContributionWindowPicker()
                .fixedSize()
        }
    }
}

/// Your summary in its own pane, beside the leaderboard, with the people directly above and below
/// you under it. It scrolls so it still fits at accessibility text sizes or in a short pane.
private struct BoardSummaryPane: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BoardSummaryView()
                AroundYou()
            }
            .padding(16)
        }
        .background(Color.ink)
        .accessibilityLabel("Your standing")
    }
}

/// The ladder from Live rank, on the board: whoever's directly above you, you, and whoever's
/// directly below, in the shared row.
private struct AroundYou: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh

    var body: some View {
        let board = RankedBoard(store)
        let entries = board.entries
        if entries.count > 1, let mine = entries.firstIndex(where: { $0.competitor.isSelf }) {
            VStack(alignment: .leading, spacing: 8) {
                FolioHeader("Around you")
                    .padding(.horizontal, 6)
                VStack(spacing: 2) {
                    ForEach(entries[max(0, mine - 1)...min(entries.count - 1, mine + 1)]) { entry in
                        PersonRowButton(login: entry.competitor.username) {
                            board.row(entry, store: store, refresh: refresh)
                        }
                    }
                }
                .padding(6)
                .tileCard()
            }
        }
    }
}

private struct InitialLoadRow: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fetching the first set of standings").font(.subheadline.weight(.medium))
                Text("This only happens once.").font(.footnote).foregroundStyle(Color.muted)
            }
        } icon: {
            ProgressView().tint(.lime)
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
            TrophyMark(size: 40)
                .padding(.bottom, 4)
            Text(everyoneHidden ? "Your circle is hidden" : "Your circle starts here")
                .font(CommittedType.display(24, relativeTo: .title2))
                .displayTracking(24)
                .multilineTextAlignment(.center)
            Text(everyoneHidden
                 ? "Show people again in People whenever you like."
                 : "Follow people on GitHub or join an organization to see them on your board automatically.")
                .font(.subheadline)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
            Button("Open People") { model.selectedTab = .people }
                .buttonStyle(LimeButtonStyle())
                .fixedSize()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .tileCard()
    }
}

/// The selected Window's board, ranked by `Ranking.order`: the list and "Around you" read the same
/// one, so their rows can't disagree.
@MainActor
private struct RankedBoard {
    let window: ContributionWindow
    let entries: [Ranking.Entry]
    /// The leader's loaded count, which shades every row's square.
    let maxContributions: Int

    init(_ store: StandingsStore) {
        window = store.selectedWindow
        let standings = store.standings(for: window)
        entries = Ranking.order(competitors: store.visibleCompetitors, standings: standings, window: window)
        maxContributions = entries.compactMap { standings[$0.competitor.username] }
            .filter { $0.lastUpdated != .distantPast }
            .map(\.contributions).max() ?? 0
    }

    /// The shared row for `entry`, with today's movement on Today, and the person's streak.
    func row(_ entry: Ranking.Entry, store: StandingsStore, refresh: RefreshCoordinator) -> StandingRow {
        StandingRow(
            rank: entry.rank,
            competitor: entry.competitor,
            standing: store.standing(for: entry.competitor.username, window: window),
            window: window,
            maxContributions: maxContributions,
            rankDelta: refresh.rankDelta(for: entry.competitor.username, in: window),
            streak: refresh.streak(for: entry.competitor.username)
        )
    }
}
