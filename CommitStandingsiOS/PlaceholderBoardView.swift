import SwiftUI

/// The shell's only screen: a board of `StandingRow`s (the single shared board row) built from
/// saved or sample standings. #41 replaces it with the real Board tab.
struct PlaceholderBoardView: View {
    let store: StandingsStore
    @State private var window: ContributionWindow = .daily

    var body: some View {
        let board = PlaceholderBoard.make(store: store, window: window)
        NavigationStack {
            List(board.rows) { row in
                StandingRow(
                    rank: row.rank,
                    competitor: row.competitor,
                    standing: row.standing,
                    window: board.window,
                    maxContributions: board.maxContributions
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .navigationTitle("Committed")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Window", selection: $window) {
                        ForEach(ContributionWindow.allCases) { window in
                            Text(window.title).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if board.isSample {
                    Text("Sample board")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }
        }
    }
}

#Preview {
    PlaceholderBoardView(store: StandingsStore(persistence: InMemoryCompetitorPersistence()))
}
