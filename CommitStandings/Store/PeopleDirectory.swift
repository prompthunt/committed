import Foundation

/// The People list on the Mac (People window) and iPhone (People tab): everyone on the roster,
/// hidden people included so every choice is reversible, alphabetical, narrowed by source and
/// a username search.
enum PeopleDirectory {
    static func people(
        _ competitors: [Competitor],
        roster: GitHubRosterSnapshot?,
        source: PeopleSourceFilter,
        query: String
    ) -> [Competitor] {
        let allowed = roster?.usernames(in: source) ?? []
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return competitors.filter { person in
            (source == .all || allowed.contains(person.username))
                && (query.isEmpty || person.username.localizedCaseInsensitiveContains(query))
        }
        .sorted { $0.username < $1.username }
    }

    /// Hide or show someone on this device's board. Hiding takes effect at once; showing
    /// someone again re-fetches just their numbers. You can't hide yourself (the store ignores it).
    @MainActor
    static func setHidden(_ hidden: Bool, username: String, store: StandingsStore, refresh: RefreshCoordinator) async {
        guard store.isHidden(username) != hidden else { return }
        store.setHidden(hidden, username: username)
        if !hidden {
            await refresh.refreshOne(username: username, reason: .visibilityChanged)
        }
    }
}
