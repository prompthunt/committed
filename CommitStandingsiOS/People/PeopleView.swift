import SwiftUI

/// The People tab. For now a read-only, alphabetical list of who's on your board with the
/// people-sync status. #42 replaces the body with search, source filters, and hide/show; keep the
/// `NavigationStack` here so pushes and toolbar items land in this tab's own stack.
struct PeopleView: View {
    @Environment(StandingsStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RosterStatusView()
                }
                Section {
                    ForEach(store.visibleCompetitors.sorted { $0.username < $1.username }) { person in
                        HStack(spacing: 12) {
                            AvatarView(username: person.username, size: 32)
                            Text(person.username)
                            if person.isSelf {
                                Text("you").font(.caption).foregroundStyle(.tint)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("On your board")
                }
            }
            .overlay {
                if store.competitors.isEmpty {
                    ContentUnavailableView(
                        "No people yet", systemImage: "person.2",
                        description: Text("Your organization members and the people you follow sync from GitHub.")
                    )
                }
            }
            .navigationTitle("People")
        }
    }
}
