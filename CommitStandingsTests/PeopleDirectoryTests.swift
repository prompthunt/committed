import Testing
import Foundation
@testable import CommitStandings

/// The People list (Mac People window and iPhone People tab): everyone alphabetically, narrowed
/// by source and a username search.
struct PeopleDirectoryTests {

    private let competitors = [
        Competitor(username: "me", isSelf: true),
        Competitor(username: "zoe", isSelf: false),
        Competitor(username: "alice", isSelf: false),
        Competitor(username: "bob", isSelf: false),
    ]

    private let roster = GitHubRosterSnapshot(
        owner: "me",
        sources: [
            GitHubRosterSource(id: "following", title: "People you follow", members: ["zoe", "Alice"]),
            GitHubRosterSource(id: "org:acme", title: "acme", members: ["bob", "alice"]),
        ],
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    private func names(_ source: PeopleSourceFilter, _ query: String = "", roster: GitHubRosterSnapshot? = nil) -> [String] {
        PeopleDirectory.people(competitors, roster: roster ?? self.roster, source: source, query: query).map(\.username)
    }

    @Test func allListsEveryoneAlphabeticallyIncludingYou() {
        #expect(names(.all) == ["alice", "bob", "me", "zoe"])
    }

    @Test func followingAndOrganizationsListOnlyThatSourcesMembers() {
        #expect(names(.following) == ["alice", "zoe"])
        #expect(names(.organizations) == ["alice", "bob"])
    }

    @Test func searchMatchesPartOfAUsernameIgnoringCaseSpacesAndAtSign() {
        #expect(names(.all, "  @AL ") == ["alice"])
        #expect(names(.all, "o") == ["bob", "zoe"])
        #expect(names(.organizations, "o") == ["bob"])
    }

    @Test func searchAndSourceWithNoMatchesIsEmpty() {
        #expect(names(.following, "bob").isEmpty)
    }

    @Test func beforePeopleSyncOnlyAllListsAnyone() {
        #expect(PeopleDirectory.people(competitors, roster: nil, source: .all, query: "").count == 4)
        #expect(PeopleDirectory.people(competitors, roster: nil, source: .following, query: "").isEmpty)
    }
}
