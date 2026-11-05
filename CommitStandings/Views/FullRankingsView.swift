import SwiftUI

/// One alphabetical list, including hidden people so every choice is reversible.
struct FullRankingsView: View {
    @Environment(StandingsStore.self) private var store
    @Environment(GitHubRoster.self) private var roster
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var source = PeopleSourceFilter.all
    @State private var searchText = ""

    private var people: [Competitor] {
        PeopleDirectory.people(in: store.competitors, roster: roster.snapshot, source: source, search: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose who appears on your leaderboard.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("People source", selection: $source) {
                    ForEach(PeopleSourceFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                RosterStatusView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            Divider()
            List(people) { person in
                PersonVisibilityRow(person: person)
            }
            .listStyle(.inset)
            .accessibilityLabel("People, alphabetical")
            .overlay {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No people found", systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Try another username or source.")
                    )
                }
            }
            Divider()
            HStack {
                Text("\(store.visibleCompetitors.count) visible · \(store.competitors.count - store.visibleCompetitors.count) hidden")
                    .foregroundStyle(.secondary)
                Spacer()
                if let owner = roster.snapshot?.owner,
                   let url = URL(string: "https://github.com/\(owner)?tab=following") {
                    Link("Following on GitHub", destination: url)
                }
            }
            .font(.caption)
            .padding(12)
        }
        .searchable(text: $searchText, prompt: "Find a GitHub username")
        .frame(minWidth: 380, idealWidth: 420, minHeight: 300, idealHeight: 480)
        .toolbar {
            ToolbarItem {
                Button("Refresh people", systemImage: "arrow.clockwise") {
                    Task { await refresh.refreshAll(reason: .manual) }
                }
                .disabled(refresh.isRefreshing || roster.isRefreshing)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismissWindow(id: FullRankingsWindow.id) }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .task {
            if roster.snapshot == nil { await refresh.refreshAll(reason: .menuOpened) }
        }
    }
}

private struct PersonVisibilityRow: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    let person: Competitor

    private var hidden: Bool { store.isHidden(person.username) }
    private var actionLabel: String {
        PeopleDirectory.visibilityActionLabel(username: person.username, hidden: hidden)
    }

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(username: person.username, size: 24)
                .opacity(hidden ? 0.5 : 1)
            Text("@\(person.username)")
                .foregroundStyle(hidden ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer()
            if person.isSelf {
                Text("You").font(.caption).foregroundStyle(.secondary)
            } else {
                if hidden {
                    Text("Hidden").font(.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Button(action: toggleVisibility) {
                    Image(systemName: hidden ? "eye.slash" : "eye")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(actionLabel)
                .accessibilityLabel(actionLabel)
                .accessibilityValue(hidden ? "Hidden" : "Visible")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if !person.isSelf {
                Button(actionLabel, action: toggleVisibility)
            }
        }
    }

    private func toggleVisibility() {
        PeopleDirectory.toggleVisibility(of: person, store: store, refresh: refresh)
    }
}
