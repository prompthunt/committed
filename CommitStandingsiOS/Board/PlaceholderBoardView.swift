import SwiftUI

/// The iPhone shell's board: the shared `StandingRow` in a list, fed by saved standings or the
/// sample. The real board (Connect GitHub, refresh, summary) replaces this in #41.
struct PlaceholderBoardView: View {
    @Environment(StandingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let board = PlaceholderBoard.make(
            competitors: store.visibleCompetitors,
            standings: store.standings(for: store.selectedWindow),
            window: store.selectedWindow
        )
        NavigationStack {
            List {
                Section {
                    ForEach(board.rows) { row in
                        StandingRow(
                            rank: row.rank,
                            competitor: row.competitor,
                            standing: row.standing,
                            window: board.window,
                            maxContributions: board.maxContributions
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Picker("Window", selection: $store.selectedWindow) {
                        ForEach(ContributionWindow.allCases) { window in
                            Text(window.shortTitle).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    .padding(.bottom, 8)
                } footer: {
                    if board.isSample {
                        Text("Sample board. Connect GitHub to see your Competitors.")
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Committed")
        }
    }
}

#Preview {
    PlaceholderBoardView()
        .environment(StandingsStore())
}
