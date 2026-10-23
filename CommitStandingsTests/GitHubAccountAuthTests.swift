import Testing
import Foundation
@testable import CommitStandings

/// Own URLProtocol so this suite never shares a static handler with the other
/// serialized suites.
final class AccountMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = AccountMockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AccountMockURLProtocol.self]
    return URLSession(configuration: config)
}

private func data(_ s: String) -> Data { Data(s.utf8) }

@Suite(.serialized)
@MainActor
struct GitHubAccountAuthTests {

    // MARK: - GitHubAccountClient

    @Test func currentUserProfile_parsesLogin() async {
        AccountMockURLProtocol.handler = { _ in (200, data(#"{"login":"addisonk","id":1}"#)) }
        let client = GitHubAccountClient(token: "gho_x", session: mockSession())
        #expect(await client.currentUserProfile()?.login == "addisonk")
    }

    @Test func following_and_orgs_and_members_parseArrays() async throws {
        AccountMockURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if path == "/user/following" { return (200, data(#"[{"login":"jordan-m"},{"login":"sam-l"}]"#)) }
            if path == "/user/orgs" { return (200, data(#"[{"login":"acme"}]"#)) }
            if path == "/orgs/acme/members" { return (200, data(#"[{"login":"sam-l"},{"login":"taylor-r"}]"#)) }
            return (404, Data())
        }
        let client = GitHubAccountClient(token: "gho_x", session: mockSession())
        #expect(try await client.following() == ["jordan-m", "sam-l"])
        #expect(try await client.organizations() == ["acme"])
        #expect(try await client.orgMembers("acme") == ["sam-l", "taylor-r"])
    }

    @Test func currentUserProfile_on401_returnsNil() async {
        AccountMockURLProtocol.handler = { _ in (401, data(#"{"message":"Bad credentials"}"#)) }
        let client = GitHubAccountClient(token: "bad", session: mockSession())
        #expect(await client.currentUserProfile() == nil)
    }

    @Test func currentUserProfile_parsesLoginAndName() async {
        AccountMockURLProtocol.handler = { _ in (200, data(#"{"login":"addisonk","name":"Addison Kowalski"}"#)) }
        let client = GitHubAccountClient(token: "gho_x", session: mockSession())
        let profile = await client.currentUserProfile()
        #expect(profile?.login == "addisonk")
        #expect(profile?.name == "Addison Kowalski")
    }

    @Test func currentUserProfile_nullName_isNil() async {
        AccountMockURLProtocol.handler = { _ in (200, data(#"{"login":"addisonk","name":null}"#)) }
        let client = GitHubAccountClient(token: "gho_x", session: mockSession())
        let profile = await client.currentUserProfile()
        #expect(profile?.login == "addisonk")
        #expect(profile?.name == nil)
    }

    // MARK: - AuthModel

    private func auth(credentials: GitHubCredentialStoring) -> AuthModel {
        AuthModel(
            credentials: credentials,
            auth: GitHubAuth(clientID: "test", session: mockSession()),
            accountFactory: { GitHubAccountClient(token: $0, session: mockSession()) }
        )
    }

    @Test func init_withStoredToken_isSignedIn() {
        let model = auth(credentials: InMemoryGitHubCredentialStore(token: "gho_x"))
        #expect(model.isSignedIn)
    }

    @Test func init_withoutToken_isSignedOut() {
        let model = auth(credentials: InMemoryGitHubCredentialStore())
        #expect(!model.isSignedIn)
    }

    @Test func signOut_clearsTokenAndReturnsToGate() {
        let credentials = InMemoryGitHubCredentialStore(token: "gho_x")
        let model = auth(credentials: credentials)
        #expect(model.isSignedIn)
        model.signOut()
        #expect(!model.isSignedIn)
        #expect(credentials.read() == nil)
    }

    @Test func refreshIdentity_signedIn_setsUsernameAndDisplayName() async {
        AccountMockURLProtocol.handler = { _ in (200, data(#"{"login":"addisonk","name":"Addison Kowalski"}"#)) }
        let model = auth(credentials: InMemoryGitHubCredentialStore(token: "gho_x"))
        await model.refreshIdentity()
        #expect(model.username == "addisonk")
        #expect(model.displayName == "Addison Kowalski")
    }

    @Test func refreshIdentity_signedOut_isNoOp() async {
        AccountMockURLProtocol.handler = { _ in (200, data(#"{"login":"addisonk","name":"Addison Kowalski"}"#)) }
        let model = auth(credentials: InMemoryGitHubCredentialStore())
        await model.refreshIdentity()
        #expect(model.username == nil)
        #expect(model.displayName == nil)
    }

    @Test func refreshIdentity_fetchFailure_preservesPriorDisplayName() async {
        AccountMockURLProtocol.handler = { _ in (200, data(#"{"login":"addisonk","name":"Addison Kowalski"}"#)) }
        let model = auth(credentials: InMemoryGitHubCredentialStore(token: "gho_x"))
        await model.refreshIdentity()
        #expect(model.displayName == "Addison Kowalski")
        // A later transient failure must not wipe the name we already have.
        AccountMockURLProtocol.handler = { _ in (401, data(#"{"message":"Bad credentials"}"#)) }
        await model.refreshIdentity()
        #expect(model.username == "addisonk")
        #expect(model.displayName == "Addison Kowalski")
    }

    @Test func paginationLoadsBeyondFirstHundredForEverySource() async throws {
        AccountMockURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(query.contains(URLQueryItem(name: "per_page", value: "100")))
            let page = query.first { $0.name == "page" }!.value!
            if page == "1" {
                return (200, try! JSONSerialization.data(withJSONObject: (1...100).map { ["login": "person-\($0)"] }))
            }
            return (200, data(#"[{"login":"person-101"}]"#))
        }
        let client = GitHubAccountClient(token: "fixture", session: mockSession())
        #expect(try await client.following().count == 101)
        #expect(try await client.organizations().count == 101)
        #expect(try await client.orgMembers("acme").last == "person-101")
    }

    @Test func failureOnLaterPageDoesNotReturnPartialPeople() async {
        AccountMockURLProtocol.handler = { request in
            if URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first(where: { $0.name == "page" })?.value == "1" {
                return (200, try! JSONSerialization.data(withJSONObject: (1...100).map { ["login": "person-\($0)"] }))
            }
            return (403, Data())
        }
        do {
            _ = try await GitHubAccountClient(token: "fixture", session: mockSession()).following()
            Issue.record("A failed second page must fail the entire source")
        } catch {}
    }

    @Test func rosterIncludesAllOrganizationsAndFollowing() async throws {
        AccountMockURLProtocol.handler = { request in
            switch request.url!.path {
            case "/user": return (200, data(#"{"login":"Octocat"}"#))
            case "/user/orgs": return (200, data(#"[{"login":"acme"},{"login":"globex"}]"#))
            case "/orgs/acme/members": return (200, data(#"[{"login":"hubot"}]"#))
            case "/orgs/globex/members": return (200, data(#"[{"login":"monalisa"}]"#))
            case "/user/following": return (200, data(#"[{"login":"steipete"}]"#))
            default: return (404, Data())
            }
        }
        let result = try await GitHubAccountClient(token: "fixture", session: mockSession()).roster()
        #expect(result.owner == "octocat")
        #expect(result.sources.map(\.id) == ["org:acme", "org:globex", "following"])
        #expect(result.sources.flatMap(\.members) == ["hubot", "monalisa", "steipete"])
    }

    @Test func organizationFailureFailsWholeRoster() async {
        AccountMockURLProtocol.handler = { request in
            switch request.url!.path {
            case "/user": return (200, data(#"{"login":"octocat"}"#))
            case "/user/orgs": return (200, data(#"[{"login":"acme"}]"#))
            case "/user/following": return (200, Data("[]".utf8))
            default: return (403, Data())
            }
        }
        do {
            _ = try await GitHubAccountClient(token: "fixture", session: mockSession()).roster()
            Issue.record("Inaccessible organization must not silently remove members")
        } catch {}
    }

    @Test func replacingRosterDeduplicatesPreservesIDsAndCountsAndRemovesDepartures() throws {
        let persistence = InMemoryCompetitorPersistence()
        let cache = InMemoryStandingsSnapshotPersistence()
        let store = StandingsStore(persistence: persistence, snapshotPersistence: cache)
        let me = try store.addSelf(username: "octocat")
        let hubot = try store.addRival(username: "hubot")
        _ = try store.addRival(username: "departed")
        store.updateStanding(Standing(username: "hubot", contributions: 42, window: .daily, lastUpdated: Date(), state: .loaded))
        store.updateStanding(Standing(username: "departed", contributions: 5, window: .daily, lastUpdated: Date(), state: .loaded))
        store.replaceRoster(owner: "Octocat", members: ["OCTOCAT", "hubot", "HUBOT", "monalisa", "invalid name"])
        #expect(store.competitors.map(\.username) == ["octocat", "hubot", "monalisa"])
        #expect(store.selfCompetitor?.id == me.id)
        #expect(store.rivals.first?.id == hubot.id)
        #expect(store.standing(for: "hubot", window: .daily)?.contributions == 42)
        #expect(store.standing(for: "departed", window: .daily) == nil)
        #expect(cache.load().map(\.username) == ["hubot"])
        #expect(StandingsStore(persistence: persistence).competitors == store.competitors)
    }

    private func snapshot(_ members: [String], owner: String = "octocat") -> GitHubRosterSnapshot {
        GitHubRosterSnapshot(owner: owner, sources: [GitHubRosterSource(id: "following", title: "People you follow", members: members)], updatedAt: Date())
    }

    @Test func rosterFailureRetainsLegacyListAndShowsError() async throws {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        _ = try store.addSelf(username: "octocat")
        _ = try store.addRival(username: "legacy-friend")
        let before = store.competitors
        let roster = GitHubRoster(store: store, credentials: InMemoryGitHubCredentialStore(token: "fixture"), fetch: { _ in throw URLError(.notConnectedToInternet) })
        await roster.refresh()
        #expect(store.competitors == before)
        #expect(roster.snapshot == nil)
        #expect(roster.errorMessage != nil)
        #expect(!roster.isRefreshing)
    }

    @Test func automaticRosterPersistsAndRestoresOffline() async throws {
        let suite = "roster-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = UserDefaultsGitHubRosterPersistence(defaults: defaults)
        let competitors = UserDefaultsCompetitorPersistence(defaults: defaults)
        let backup = UserDefaultsCompetitorPersistence(defaults: defaults, key: "manual-backup")
        let store = StandingsStore(persistence: competitors)
        _ = try store.addSelf(username: "octocat")
        _ = try store.addRival(username: "manual-friend")
        let expected = snapshot(["hubot", "monalisa", "octocat"])
        let credentials = InMemoryGitHubCredentialStore(token: "fixture")
        let roster = GitHubRoster(store: store, credentials: credentials, persistence: persistence, legacyBackup: backup, fetch: { _ in expected })
        await roster.refresh()
        #expect(store.competitors.map(\.username) == ["octocat", "hubot", "monalisa"])
        #expect(backup.load().map(\.username) == ["octocat", "manual-friend"])
        let ids = store.competitors.map(\.id)
        let relaunchedStore = StandingsStore(persistence: competitors)
        let relaunched = GitHubRoster(store: relaunchedStore, credentials: credentials, persistence: persistence, fetch: { _ in throw URLError(.notConnectedToInternet) })
        await relaunched.refresh()
        #expect(relaunched.snapshot == expected)
        #expect(relaunchedStore.competitors.map(\.id) == ids)
        #expect(relaunched.errorMessage != nil)
        roster.disconnect()
        #expect(persistence.load() == nil)
        #expect(store.competitors.isEmpty)
    }

    @Test func successfulEmptySourcesRemoveOldPeopleButKeepSelf() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "octocat", members: ["hubot"])
        let expected = snapshot([])
        let roster = GitHubRoster(store: store, credentials: InMemoryGitHubCredentialStore(token: "fixture"), fetch: { _ in expected })
        await roster.refresh()
        #expect(store.competitors.map(\.username) == ["octocat"])
        #expect(roster.errorMessage == nil)
    }

    @Test func accountSwitchClearsPriorCountsEvenForSharedPeople() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "old-account", members: ["hubot"])
        store.updateStanding(Standing(username: "hubot", contributions: 42, window: .daily, lastUpdated: Date(), state: .loaded))
        let expected = snapshot(["hubot"], owner: "new-account")
        let roster = GitHubRoster(store: store, credentials: InMemoryGitHubCredentialStore(token: "fixture"), fetch: { _ in expected })
        await roster.refresh()
        #expect(store.selfCompetitor?.username == "new-account")
        #expect(store.standings.isEmpty)
    }

    @Test func signOutDuringFetchCannotRepopulateList() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        let gate = RosterFetchGate()
        let credentials = InMemoryGitHubCredentialStore(token: "fixture")
        let roster = GitHubRoster(store: store, credentials: credentials, fetch: { _ in await gate.fetch() })
        let task = Task { await roster.refresh() }
        await gate.waitUntilStarted()
        credentials.clear()
        roster.disconnect()
        await gate.finish(snapshot(["hubot"]))
        await task.value
        #expect(store.competitors.isEmpty)
        #expect(roster.snapshot == nil)
        #expect(!roster.isRefreshing)
    }

    @Test func cancelledFetchPreservesListWithoutReportingNetworkFailure() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        store.replaceRoster(owner: "octocat", members: ["previous"])
        let before = store.competitors
        let gate = RosterFetchGate()
        let roster = GitHubRoster(store: store, credentials: InMemoryGitHubCredentialStore(token: "fixture"), fetch: { _ in await gate.fetch() })
        let task = Task { await roster.refresh() }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.finish(snapshot(["different"]))
        await task.value
        #expect(store.competitors == before)
        #expect(roster.snapshot == nil)
        #expect(roster.errorMessage == nil)
    }

    @Test func rosterRechecksAfterFifteenMinutes() async {
        let clock = MutableClock(Date())
        let counter = RosterFetchCounter()
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        let expected = snapshot(["hubot"])
        let roster = GitHubRoster(store: store, credentials: InMemoryGitHubCredentialStore(token: "fixture"), now: { clock.date }, fetch: { _ in
            await counter.increment()
            return expected
        })
        await roster.refresh()
        clock.date.addTimeInterval(899)
        await roster.refresh()
        #expect(await counter.count == 1)
        clock.date.addTimeInterval(1)
        await roster.refresh()
        #expect(await counter.count == 2)
    }

    @Test func repeatedMenuOpensThrottleAndManualRefreshRetries() async {
        let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
        let counter = RosterFetchCounter()
        let expected = snapshot(["hubot"])
        let roster = GitHubRoster(store: store, credentials: InMemoryGitHubCredentialStore(token: "fixture"), fetch: { _ in
            await counter.increment()
            return expected
        })
        await roster.refresh()
        await roster.refresh()
        #expect(await counter.count == 1)
        await roster.refresh(force: true)
        #expect(await counter.count == 2)
    }
}

private actor RosterFetchCounter {
    var count = 0
    func increment() { count += 1 }
}

private actor RosterFetchGate {
    private var continuation: CheckedContinuation<GitHubRosterSnapshot, Never>?
    func fetch() async -> GitHubRosterSnapshot {
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }
    func finish(_ snapshot: GitHubRosterSnapshot) { continuation?.resume(returning: snapshot) }
}
