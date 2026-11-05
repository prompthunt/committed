import SwiftUI

/// The People tab: everyone on your board alphabetically, hidden people included so every
/// choice is reversible, with search and All / Following / Organizations. Filtering is the
/// Mac People window's (`PeopleDirectory`), and hide/show goes through `AppModel.setHidden`.
struct PeopleView: View {
    @Environment(AppModel.self) private var app
    @State private var source = PeopleSourceFilter.all
    @State private var searchText = ""

    var body: some View {
        let people = PeopleDirectory.people(
            app.store.competitors, roster: app.roster.snapshot, source: source, query: searchText
        )
        NavigationStack {
            List {
                Section {
                    RosterStatusView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Choose who appears on your leaderboard.")
                        .textCase(nil)
                }
                if !people.isEmpty {
                    Section {
                        ForEach(people) { person in
                            PersonRow(person: person)
                        }
                    } footer: {
                        PeopleFooter()
                    }
                }
            }
            .overlay { PeopleEmptyState(isEmpty: people.isEmpty, isSearching: !searchText.isEmpty || source != .all) }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a GitHub username")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .refreshable { await app.refresh.refreshAll(reason: .manual) }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Too wide for a vertical bar, so it stays horizontal in the navigation bar,
                // like the Board's Window switch.
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $source) {
                        ForEach(PeopleSourceFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }
}

/// One person: avatar, handle, and a show/hide switch (you can't hide yourself).
private struct PersonRow: View {
    @Environment(AppModel.self) private var app
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 32
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let person: Competitor

    private var hidden: Bool { app.store.isHidden(person.username) }
    private var actionLabel: String {
        "\(hidden ? "Show" : "Hide") @\(person.username)\(hidden ? " on" : " from") leaderboard"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Capped so the handle keeps the room at accessibility text sizes.
            AvatarView(username: person.username, size: min(avatarSize, 48))
                .opacity(hidden ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(person.username)")
                    .foregroundStyle(hidden ? .secondary : .primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                if person.isSelf || hidden {
                    Text(person.isSelf ? "You" : "Hidden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !person.isSelf {
                Button(actionLabel, systemImage: hidden ? "eye.slash" : "eye", action: toggle)
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .foregroundStyle(hidden ? .secondary : Color.accentColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.borderless)
                    .accessibilityValue(hidden ? "Hidden" : "Visible")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if !person.isSelf {
                Button(actionLabel, action: toggle)
            }
        }
    }

    private func toggle() {
        let shouldHide = !hidden
        Task { await app.setHidden(shouldHide, username: person.username) }
    }
}

/// "5 visible · 1 hidden", and where to change who you follow.
private struct PeopleFooter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let store = app.store
        VStack(alignment: .leading, spacing: 6) {
            Text("\(store.visibleCompetitors.count) visible · \(store.competitors.count - store.visibleCompetitors.count) hidden")
            Text("Hiding someone only changes this iPhone’s board. It never unfollows anyone on GitHub.")
            if let owner = app.roster.snapshot?.owner,
               let url = URL(string: "https://github.com/\(owner)?tab=following") {
                Link("Following on GitHub", destination: url)
            }
        }
    }
}

private struct PeopleEmptyState: View {
    @Environment(GitHubRoster.self) private var roster
    let isEmpty: Bool
    let isSearching: Bool

    var body: some View {
        if isEmpty {
            if isSearching {
                ContentUnavailableView(
                    "No people found", systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Try another username or source.")
                )
            } else if roster.errorMessage == nil {
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
}
