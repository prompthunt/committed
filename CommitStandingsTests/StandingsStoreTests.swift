import Testing
import Foundation
@testable import CommitStandings

@MainActor
struct StandingsStoreTests {

    @Test func hiddenPersonStaysManageableButLeavesEveryRanking() {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: ["old-contractor", "friend"])
        let contractorID = store.competitors.first { $0.username == "old-contractor" }!.id
        for window in ContributionWindow.allCases {
            for (username, count) in [("old-contractor", 99), ("friend", 12), ("me", 6)] {
                store.updateStanding(Standing(username: username, contributions: count, window: window, lastUpdated: .now, state: .loaded))
            }
        }
        store.setHidden(true, username: "@OLD-CONTRACTOR")
        #expect(store.isHidden("old-contractor"))
        #expect(store.competitors.count == 3)
        #expect(store.rivals.map(\.username) == ["friend"])
        for window in ContributionWindow.allCases {
            let entries = Ranking.order(competitors: store.visibleCompetitors, standings: store.standings(for: window), window: window)
            #expect(entries.map(\.competitor.username) == ["friend", "me"])
            #expect(entries.map(\.rank) == [1, 2])
            #expect(store.standing(for: "old-contractor", window: window)?.contributions == 99)
        }
        store.setHidden(false, username: "old-contractor")
        #expect(store.visibleCompetitors.count == 3)
        #expect(store.competitors.first { $0.username == "old-contractor" }?.id == contractorID)
    }

    @Test func visibilitySurvivesRosterRefreshAndDepartingThenReturning() {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: ["old-contractor", "friend"])
        store.setHidden(true, username: "old-contractor")
        store.replaceRoster(owner: "me", members: ["old-contractor", "friend", "new-person", "OLD-CONTRACTOR"])
        #expect(!store.visibleCompetitors.contains { $0.username == "old-contractor" })
        #expect(store.visibleCompetitors.contains { $0.username == "new-person" })
        store.replaceRoster(owner: "me", members: ["friend"])
        store.replaceRoster(owner: "me", members: ["old-contractor", "friend"])
        #expect(store.isHidden("old-contractor"))
        #expect(store.visibleCompetitors.count == 2)
    }

    @Test func visibilityPersistsLocallyAcrossRelaunchAndAccountSwitch() throws {
        let suite = "hidden-people-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let people = UserDefaultsCompetitorPersistence(defaults: defaults)
        let hidden = UserDefaultsHiddenPeoplePersistence(defaults: defaults)
        let store = StandingsStore(persistence: people, hiddenPeoplePersistence: hidden)
        store.replaceRoster(owner: "first-account", members: ["shared-person"])
        store.setHidden(true, username: "shared-person")
        let relaunched = StandingsStore(persistence: people, hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence(defaults: defaults))
        #expect(relaunched.isHidden("shared-person"))
        #expect(relaunched.visibleCompetitors.map(\.username) == ["first-account"])
        // Sign-out clears the roster but keeps account-scoped preferences.
        relaunched.reset()
        relaunched.replaceRoster(owner: "second-account", members: ["shared-person"])
        #expect(!relaunched.isHidden("shared-person"))
        relaunched.reset()
        relaunched.replaceRoster(owner: "first-account", members: ["shared-person"])
        #expect(relaunched.isHidden("shared-person"))
        relaunched.setHidden(false, username: "shared-person")
        let unhidden = StandingsStore(persistence: people, hiddenPeoplePersistence: hidden)
        #expect(!unhidden.isHidden("shared-person"))
        #expect(unhidden.visibleCompetitors.count == 2)
    }

    @Test func cannotHideSelfOrUnknownPerson() {
        let persistence = InMemoryHiddenPeoplePersistence()
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence(), hiddenPeoplePersistence: persistence)
        store.replaceRoster(owner: "me", members: ["friend"])
        store.setHidden(true, username: "me")
        store.setHidden(true, username: "unknown")
        #expect(!store.isHidden("me"))
        #expect(store.visibleCompetitors.count == 2)
        #expect(persistence.load().isEmpty)
    }

    @Test func sourceFiltersDeduplicateAndKeepHiddenPeopleAvailable() {
        let roster = GitHubRosterSnapshot(owner: "me", sources: [
            GitHubRosterSource(id: "org:current", title: "current", members: ["me", "Org-Only", "both"]),
            GitHubRosterSource(id: "org:old", title: "old", members: ["both", "old-contractor"]),
            GitHubRosterSource(id: "following", title: "People you follow", members: ["Follow-Only", "both"])
        ], updatedAt: .now)
        #expect(roster.usernames(in: .following) == ["follow-only", "both"])
        #expect(roster.usernames(in: .organizations) == ["me", "org-only", "both", "old-contractor"])
        #expect(roster.usernames(in: .all).count == 5)
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "me", members: roster.sources.flatMap(\.members))
        store.setHidden(true, username: "both")
        #expect(roster.usernames(in: .following).contains("both"))
        #expect(roster.usernames(in: .organizations).contains("both"))
        #expect(!store.visibleCompetitors.contains { $0.username == "both" })
    }

    @Test func nineteenTrackedPeopleSurviveRelaunchAndAllTimeWindows() throws {
        let suite = "Committed.TrackingRegression.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = UserDefaultsCompetitorPersistence(defaults: defaults)
        let store = StandingsStore(persistence: persistence)
        try store.addSelf(username: "me")
        for number in 1...18 { try store.addRival(username: "rival-\(number)") }
        let expectedIDs = Set(store.competitors.map(\.id))

        let reloaded = StandingsStore(persistence: persistence)
        #expect(reloaded.competitors.count == 19)
        for window in ContributionWindow.allCases {
            // An unloaded person and a failed request must still remain in the list.
            reloaded.updateStanding(Standing(username: "rival-18", contributions: 100,
                window: window, lastUpdated: .now, state: .loaded))
            reloaded.updateStanding(Standing(username: "rival-1", contributions: 0,
                window: window, lastUpdated: .distantPast, state: .failed("Offline")))
            let ranked = Ranking.order(competitors: reloaded.competitors,
                standings: reloaded.standings(for: window), window: window)
            #expect(ranked.count == 19)
            #expect(Set(ranked.map(\.id)) == expectedIDs)
            #expect(ranked.filter { $0.competitor.isSelf }.count == 1)
        }
        #expect(persistence.load().count == 19)
    }

    @Test func reset_clearsCompetitorsAndPersistsEmpty() throws {
        let competitors = InMemoryCompetitorPersistence()
        let store = StandingsStore(persistence: competitors)
        _ = try store.addSelf(username: "addisonk")
        _ = try store.addRival(username: "octocat")

        store.reset()
        #expect(store.competitors.isEmpty)
        #expect(!store.hasSelf)

        // Persisted empty: a fresh store reloads to nothing.
        let reloaded = StandingsStore(persistence: competitors)
        #expect(reloaded.competitors.isEmpty)
    }

    @Test func standings_persistAcrossReload_asLoaded() throws {
        let competitors = InMemoryCompetitorPersistence()
        let snapshot = InMemoryStandingsSnapshotPersistence()
        let store = StandingsStore(persistence: competitors, snapshotPersistence: snapshot)
        _ = try store.addSelf(username: "addisonk")
        store.updateStanding(Standing(
            username: "addisonk", contributions: 12,
            window: .daily, lastUpdated: Date(timeIntervalSince1970: 1_700_000_000), state: .loaded
        ))

        // A fresh store (same backing stores) restores the numbers immediately, as
        // `.loaded` — so the board renders instead of cold-loading every launch.
        let reloaded = StandingsStore(persistence: competitors, snapshotPersistence: snapshot)
        let restored = reloaded.standing(for: "addisonk", window: .daily)
        #expect(restored?.contributions == 12)
        #expect(restored?.state == .loaded)
    }

    @Test func standings_inFlightPlaceholder_notPersisted() throws {
        let competitors = InMemoryCompetitorPersistence()
        let snapshot = InMemoryStandingsSnapshotPersistence()
        let store = StandingsStore(persistence: competitors, snapshotPersistence: snapshot)
        _ = try store.addSelf(username: "addisonk")
        store.markLoading(username: "addisonk", window: .daily) // distantPast, no data yet
        // Nothing data-bearing was written, so the snapshot stays empty and a reload
        // shows no stale placeholder.
        let reloaded = StandingsStore(persistence: competitors, snapshotPersistence: snapshot)
        #expect(reloaded.standing(for: "addisonk", window: .daily) == nil)
    }

    @Test func reset_clearsStandingsSnapshot() throws {
        let competitors = InMemoryCompetitorPersistence()
        let snapshot = InMemoryStandingsSnapshotPersistence()
        let store = StandingsStore(persistence: competitors, snapshotPersistence: snapshot)
        _ = try store.addSelf(username: "addisonk")
        store.updateStanding(Standing(
            username: "addisonk", contributions: 1,
            window: .daily, lastUpdated: Date(timeIntervalSince1970: 1_700_000_000), state: .loaded
        ))
        store.reset()
        #expect(snapshot.load().isEmpty)
    }

    @Test func addSelfWhenEmpty_setsIsSelfAndPersists() throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        let me = try store.addSelf(username: "addisonk")
        #expect(me.isSelf)
        #expect(store.selfCompetitor?.username == "addisonk")
        #expect(store.competitors.count == 1)
    }

    @Test func addSelf_persistsAcrossReload() throws {
        let persistence = InMemoryCompetitorPersistence()
        let store = StandingsStore(persistence: persistence)
        _ = try store.addSelf(username: "addisonk")
        let reloaded = StandingsStore(persistence: persistence)
        #expect(reloaded.selfCompetitor?.username == "addisonk")
    }

    @Test func addRivalBeforeSelf_isRejected() {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        #expect(throws: CompetitorMutationError.selfRequiredFirst) {
            try store.addRival(username: "octocat")
        }
        #expect(store.competitors.isEmpty)
    }

    @Test func duplicateUsername_caseInsensitive_isRejected() throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "@Addisonk")
        #expect(throws: CompetitorMutationError.duplicateUsername) {
            try store.addRival(username: "addisonk")
        }
    }

    @Test func removeSelf_isRejected_removeRival_drops() throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        let me = try store.addSelf(username: "addisonk")
        let rival = try store.addRival(username: "octocat")
        #expect(throws: CompetitorMutationError.cannotRemoveSelf) {
            try store.remove(id: me.id)
        }
        try store.remove(id: rival.id)
        #expect(store.competitors.map(\.username) == ["addisonk"])
    }

    @Test func renameSelf_keepsIsSelf_andPersists() throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        let me = try store.addSelf(username: "addisonk")
        let updated = try store.rename(id: me.id, to: "addison")
        #expect(updated.isSelf)
        #expect(store.selfCompetitor?.username == "addison")
    }

    @Test func invalidUsername_isRejected() {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        #expect(throws: CompetitorMutationError.invalidUsername) {
            try store.addSelf(username: "   ")
        }
        #expect(throws: CompetitorMutationError.invalidUsername) {
            try store.addSelf(username: "has space")
        }
        #expect(throws: CompetitorMutationError.invalidUsername) {
            try store.addSelf(username: "--dashes")
        }
    }

    @Test func mutations_roundTripThroughPersistence() throws {
        let persistence = InMemoryCompetitorPersistence()
        let store = StandingsStore(persistence: persistence)
        _ = try store.addSelf(username: "addisonk")
        _ = try store.addRival(username: "octocat")
        _ = try store.addRival(username: "torvalds")
        let reloaded = StandingsStore(persistence: persistence)
        #expect(reloaded.competitors.map(\.username) == ["addisonk", "octocat", "torvalds"])
        #expect(reloaded.selfCompetitor?.username == "addisonk")
    }

    @Test func standings_retainedPerWindow_switchingDoesNotClobber() throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        store.updateStanding(Standing(username: "addisonk", contributions: 100, window: .daily, lastUpdated: .now, state: .loaded))
        store.updateStanding(Standing(username: "addisonk", contributions: 200, window: .weekly, lastUpdated: .now, state: .loaded))
        // Each window keeps its own data; the weekly write did not overwrite daily.
        #expect(store.standing(for: "addisonk", window: .daily)?.contributions == 100)
        #expect(store.standing(for: "addisonk", window: .weekly)?.contributions == 200)
    }

    @Test func updateStanding_forDroppedCompetitor_isIgnored() throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "addisonk")
        let stale = Standing(username: "ghost", contributions: 5, window: .daily, lastUpdated: Date(), state: .loaded)
        store.updateStanding(stale)
        #expect(store.standing(for: "ghost", window: .daily) == nil)
    }
}

@MainActor
struct UsernameNormalizationTests {
    @Test func stripsAtAndLowercases() {
        #expect(UsernameNormalization.normalize("@Addisonk") == "addisonk")
    }
    @Test func rejectsTrailingHyphen() {
        #expect(UsernameNormalization.normalize("addisonk-") == nil)
    }
    @Test func rejectsConsecutiveHyphens() {
        #expect(UsernameNormalization.normalize("addisonk--cool") == nil)
    }
    @Test func rejectsEmpty() {
        #expect(UsernameNormalization.normalize("   ") == nil)
    }
    @Test func acceptsValidHandle() {
        #expect(UsernameNormalization.normalize("torvalds") == "torvalds")
        #expect(UsernameNormalization.normalize("kowal-ski") == "kowal-ski")
    }
}
