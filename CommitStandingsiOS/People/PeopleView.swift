import SwiftUI

/// The People tab: everyone on your board alphabetically, hidden people included, with search,
/// the All / Following / Organizations filter, and a hide/show control per person. The list,
/// filter, and visibility rules are the Mac People window's (`PeopleDirectory`).
struct PeopleView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            PeopleList(searchText: searchText)
                .navigationTitle("People")
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Find a GitHub username"
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .refreshable { await model.pullToRefresh() }
        }
    }
}

private struct PeopleList: View {
    @Environment(StandingsStore.self) private var store
    @Environment(GitHubRoster.self) private var roster
    // The filter sits in the list rather than the toolbar: three segments are too wide for the
    // iPhone Duo's vertical bars, and it has to work without an active search.
    @State private var source = PeopleSourceFilter.all
    let searchText: String

    var body: some View {
        let people = PeopleDirectory.people(
            in: store.competitors, roster: roster.snapshot, source: source, search: searchText
        )
        let hiddenCount = store.competitors.count - store.visibleCompetitors.count
        List {
            Section {
                Picker("People source", selection: $source) {
                    ForEach(PeopleSourceFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                // Full width, the segments would cross a book-style fold on the inner display.
                .avoidingFold()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                VStack(alignment: .leading, spacing: 8) {
                    RosterStatusView()
                    Text("Choose who appears on your board. Hidden people stay here so you can show them again.")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if !people.isEmpty {
                Section {
                    ForEach(people) { person in
                        PersonVisibilityRow(person: person)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.hairline)
                    }
                } header: {
                    FolioHeader("\(store.visibleCompetitors.count) on your board · \(hiddenCount) hidden")
                } footer: {
                    if let owner = roster.snapshot?.owner,
                       let url = URL(string: "https://github.com/\(owner)?tab=following") {
                        Link(destination: url) {
                            Label("Who you follow on GitHub", systemImage: "arrow.up.right")
                                .labelStyle(TrailingIconLabelStyle())
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.top, 8)
                    }
                }
            }
        }
        .listStyle(.plain)
        .inkScreen()
        .accessibilityLabel("People, alphabetical")
        .overlay {
            if store.competitors.isEmpty {
                ContentUnavailableView(
                    "No people yet", systemImage: "person.2",
                    description: Text("Your organization members and the people you follow sync from GitHub.")
                )
            } else if people.isEmpty {
                ContentUnavailableView(
                    "No people found", systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Try another username or source.")
                )
            }
        }
    }
}

/// One person with their hide/show control. You can't hide yourself, so your row has no control.
private struct PersonVisibilityRow: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let person: Competitor

    private var hidden: Bool { store.isHidden(person.username) }
    private var actionLabel: String {
        PeopleDirectory.visibilityActionLabel(username: person.username, hidden: hidden)
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(username: person.username, size: 36)
                .overlay { Circle().strokeBorder(Color.lime.opacity(person.isSelf ? 0.6 : 0), lineWidth: 1.5) }
                .saturation(hidden ? 0 : 1)
                .opacity(hidden ? 0.45 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("@\(person.username)")
                    .font(.body.weight(person.isSelf ? .semibold : .regular))
                    .foregroundStyle(hidden ? Color.muted : .white)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                if person.isSelf {
                    Text("you")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.lime, in: .capsule)
                        .foregroundStyle(Color.onLime)
                } else if hidden {
                    Text("Hidden from your board").font(.caption).foregroundStyle(Color.muted)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if !person.isSelf {
                Button(action: toggleVisibility) {
                    Image(systemName: hidden ? "eye.slash" : "eye")
                        .imageScale(.large)
                        .fontWeight(.semibold)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(hidden ? Color.muted : Color.lime)
                .accessibilityLabel(actionLabel)
                .accessibilityValue(hidden ? "Hidden" : "Visible")
            }
        }
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

/// Title, then the icon: "Who you follow on GitHub ↗".
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
