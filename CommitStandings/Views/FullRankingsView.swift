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
        let allowed = roster.snapshot?.usernames(in: source) ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return store.competitors.filter { person in
            (source == .all || allowed.contains(person.username))
                && (query.isEmpty || person.username.localizedCaseInsensitiveContains(query))
        }
        .sorted { $0.username < $1.username }
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
        "\(hidden ? "Show" : "Hide") @\(person.username)\(hidden ? " on" : " from") leaderboard"
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
        guard !person.isSelf else { return }
        let shouldHide = !hidden
        store.setHidden(shouldHide, username: person.username)
        if !shouldHide {
            Task { await refresh.refreshOne(username: person.username, reason: .visibilityChanged) }
        }
    }
}

/// Status also lives on the board so an offline or permission failure is never hidden.
struct RosterStatusView: View {
    @Environment(GitHubRoster.self) private var roster
    @Environment(RefreshCoordinator.self) private var refresh

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if roster.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Syncing people from GitHub…")
                }
            } else if let error = roster.errorMessage {
                Text(error).foregroundStyle(.orange)
                HStack {
                    Text(roster.snapshot == nil ? "Your saved list hasn’t changed." : "Showing your last synced people.")
                    Button("Retry") { Task { await refresh.refreshAll(reason: .manual) } }
                        .disabled(refresh.isRefreshing)
                }
            } else if let snapshot = roster.snapshot {
                Text("Synced \(snapshot.updatedAt, style: .relative) ago")
            } else {
                Text("Your people will sync from GitHub automatically.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
