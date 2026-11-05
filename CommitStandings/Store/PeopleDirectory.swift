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

    /// Hide or show someone on this device's board. The change applies before this returns, so
    /// quick repeated taps toggle reliably. Showing someone again also re-fetches just their
    /// numbers; that refresh is the returned task. You can't hide yourself (the store ignores it).
    @MainActor @discardableResult
    static func setHidden(
        _ hidden: Bool, username: String, store: StandingsStore, refresh: RefreshCoordinator
    ) -> Task<Void, Never>? {
        guard store.isHidden(username) != hidden else { return nil }
        store.setHidden(hidden, username: username)
        guard !hidden, !store.isHidden(username) else { return nil }
        return Task { await refresh.refreshOne(username: username, reason: .visibilityChanged) }
    }
}
