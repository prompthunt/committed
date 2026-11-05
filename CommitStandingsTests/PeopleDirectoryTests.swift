import Testing
import Foundation
@testable import CommitStandings

/// People (the Mac window and the iPhone tab) lists everyone alphabetically, hidden people
/// included, narrowed by a source filter and a username search.
@MainActor
struct PeopleDirectoryTests {
    private let snapshot = GitHubRosterSnapshot(owner: "sam", sources: [
        GitHubRosterSource(id: "following", title: "Following", members: ["Maya-Chen", "devon"]),
        GitHubRosterSource(id: "org", title: "Acme", members: ["priya", "devon", "lee"]),
    ], updatedAt: Date(timeIntervalSince1970: 0))

    private func store() -> StandingsStore {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "sam", members: ["maya-chen", "devon", "priya", "lee"])
        return store
    }

    private func names(_ people: [Competitor]) -> [String] { people.map(\.username) }

    @Test func allListsEveryoneAlphabeticallyIncludingHiddenPeople() {
        let store = store()
        store.setHidden(true, username: "lee")
        let people = PeopleDirectory.people(in: store.competitors, roster: snapshot, source: .all, search: "")
        #expect(names(people) == ["devon", "lee", "maya-chen", "priya", "sam"])
    }

    @Test func followingAndOrganizationsListOnlyThatSource() {
        let store = store()
        #expect(names(PeopleDirectory.people(in: store.competitors, roster: snapshot, source: .following, search: ""))
            == ["devon", "maya-chen"])
        #expect(names(PeopleDirectory.people(in: store.competitors, roster: snapshot, source: .organizations, search: ""))
            == ["devon", "lee", "priya"])
    }

    @Test func withoutASyncedRosterOnlyAllListsPeople() {
        let store = store()
        #expect(PeopleDirectory.people(in: store.competitors, roster: nil, source: .all, search: "").count == 5)
        #expect(PeopleDirectory.people(in: store.competitors, roster: nil, source: .following, search: "").isEmpty)
        #expect(PeopleDirectory.people(in: store.competitors, roster: nil, source: .organizations, search: "").isEmpty)
    }

    @Test func searchIgnoresCaseSurroundingSpacesAndALeadingAt() {
        let store = store()
        #expect(names(PeopleDirectory.people(in: store.competitors, roster: snapshot, source: .all, search: "  @MAYA ")) == ["maya-chen"])
        #expect(names(PeopleDirectory.people(in: store.competitors, roster: snapshot, source: .all, search: "e")) == ["devon", "lee", "maya-chen"])
        #expect(PeopleDirectory.people(in: store.competitors, roster: snapshot, source: .all, search: "   ").count == 5)
    }

    @Test func searchAndSourceCombine() {
        let store = store()
        #expect(names(PeopleDirectory.people(in: store.competitors, roster: snapshot, source: .organizations, search: "e"))
            == ["devon", "lee"])
    }

    @Test func hidingTakesSomeoneOffTheBoardAtOnceAndShowingLoadsTheirCounts() async {
        let store = store()
        let client = StubFetcher()
        await client.setSuccess(contributions: 9, for: "lee")
        let refresh = RefreshCoordinator(store: store, client: client, interval: 99999)
        let lee = store.competitors.first { $0.username == "lee" }!

        // Hiding applies before returning (so a quick second tap sees it) and fetches nothing.
        #expect(PeopleDirectory.toggleVisibility(of: lee, store: store, refresh: refresh) == nil)
        #expect(store.isHidden("lee"))
        #expect(!store.visibleCompetitors.contains { $0.username == "lee" })
        #expect(await client.calls(for: "lee") == 0)

        let loading = PeopleDirectory.toggleVisibility(of: lee, store: store, refresh: refresh)
        #expect(!store.isHidden("lee"))
        #expect(store.visibleCompetitors.contains { $0.username == "lee" })
        await loading?.value
        #expect(await client.calls(for: "lee") == 1)
        #expect(store.standing(for: "lee", window: .daily)?.contributions == 9)
    }

    @Test func youCannotHideYourself() async {
        let store = store()
        let client = StubFetcher()
        let refresh = RefreshCoordinator(store: store, client: client, interval: 99999)
        let me = store.selfCompetitor!
        #expect(PeopleDirectory.toggleVisibility(of: me, store: store, refresh: refresh) == nil)
        #expect(!store.isHidden("sam"))
        #expect(store.visibleCompetitors.contains { $0.username == "sam" })
        #expect(await client.calls(for: "sam") == 0)
    }
}
