import Foundation

/// What People shows, shared by the Mac People window and the iPhone People tab: everyone on the
/// roster in alphabetical order, hidden people included so every choice can be undone, narrowed
/// by a source filter and a username search.
enum PeopleDirectory {
    /// `.all` lists everyone even before the roster has synced. Following and Organizations need
    /// the synced roster to know who came from where, so they are empty until then.
    static func people(
        in competitors: [Competitor],
        roster: GitHubRosterSnapshot?,
        source: PeopleSourceFilter,
        search: String
    ) -> [Competitor] {
        let allowed = roster?.usernames(in: source) ?? []
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return competitors.filter { person in
            (source == .all || allowed.contains(person.username))
                && (query.isEmpty || person.username.localizedCaseInsensitiveContains(query))
        }
        .sorted { $0.username < $1.username }
    }
}

extension PeopleDirectory {
    /// Hide or show someone from the board. The change applies before this returns, so the board,
    /// rankings, and a quick second tap all see it at once. Showing someone also fetches their
    /// counts for the current Window; that fetch is returned so callers can await it. You can't
    /// hide yourself.
    @MainActor
    @discardableResult
    static func toggleVisibility(
        of person: Competitor, store: StandingsStore, refresh: RefreshCoordinator
    ) -> Task<Void, Never>? {
        guard !person.isSelf else { return nil }
        let shouldHide = !store.isHidden(person.username)
        store.setHidden(shouldHide, username: person.username)
        guard !shouldHide else { return nil }
        return Task { await refresh.refreshOne(username: person.username, reason: .visibilityChanged) }
    }
}

extension PeopleDirectory {
    /// The hide/show control's label, for VoiceOver and the Mac tooltip.
    static func visibilityActionLabel(username: String, hidden: Bool) -> String {
        "\(hidden ? "Show" : "Hide") @\(username)\(hidden ? " on" : " from") leaderboard"
    }
}
