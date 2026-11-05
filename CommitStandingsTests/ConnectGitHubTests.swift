import Foundation
import Testing
@testable import CommitStandings

/// Fake GitHub for the whole Connect GitHub path: the device-code and token endpoints on
/// github.com and `/user` on the API. Its own static handler, so it never races the other suites.
final class ConnectMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> Result<(Int, Data), URLError>)?
    nonisolated(unsafe) static var requests: [(path: String, body: String)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append((request.url?.path ?? "", Self.body(of: request)))
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        switch handler(request) {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .success(let (status, data)):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}

    /// URLSession hands URLProtocol the body as a stream, not `httpBody`.
    private static func body(of request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConnectMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private let deviceCodeJSON = #"{"device_code":"dev-1","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#

private func json(_ string: String, status: Int = 200) -> Result<(Int, Data), URLError> {
    .success((status, Data(string.utf8)))
}

/// Mutable state shared with the URLProtocol handler and the injected clock.
private final class Script: @unchecked Sendable {
    var tokenPolls = 0
    var now = Date(timeIntervalSince1970: 1_000_000)
}

private func formFields(_ body: String) -> [String: String] {
    var fields: [String: String] = [:]
    for pair in body.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        fields[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
    }
    return fields
}

@MainActor
@Suite(.serialized)
struct ConnectGitHubTests {
    private func services(
        script: Script,
        roster: @escaping @Sendable (String) async throws -> GitHubRosterSnapshot = { _ in
            GitHubRosterSnapshot(owner: "me", sources: [], updatedAt: Date(timeIntervalSince1970: 0))
        },
        contributions: StubFetcher = StubFetcher(),
        credentials: InMemoryGitHubCredentialStore = InMemoryGitHubCredentialStore()
    ) -> CommittedServices {
        ConnectMockURLProtocol.requests = []
        let session = ConnectMockURLProtocol.session
        return CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: credentials,
            contributions: contributions,
            gitHubAuth: GitHubAuth(
                clientID: GitHubConfig.clientID, scope: GitHubConfig.scope, session: session,
                sleep: { _ in }, now: { script.now }
            ),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: roster,
            refreshInterval: 9_999,
            now: { script.now }
        )
    }

    @Test func connectRequestsOnlyReadUserAndReadOrg() async {
        let script = Script()
        ConnectMockURLProtocol.handler = { request in
            request.url?.path == "/login/device/code" ? json(deviceCodeJSON) : json(#"{"error":"access_denied"}"#)
        }
        let app = services(script: script)
        await app.auth.signIn()

        let codeRequest = ConnectMockURLProtocol.requests.first { $0.path == "/login/device/code" }
        let fields = formFields(codeRequest?.body ?? "")
        #expect(fields["client_id"] == GitHubConfig.clientID)
        #expect(Set((fields["scope"] ?? "").split(separator: " ").map(String.init)) == ["read:user", "read:org"])
    }

    @Test func approvalSavesTheTokenThenLoadsAndRanksYourPeople() async throws {
        let script = Script()
        ConnectMockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/login/device/code": return json(deviceCodeJSON)
            case "/login/oauth/access_token":
                script.tokenPolls += 1
                return script.tokenPolls < 3 ? json(#"{"error":"authorization_pending"}"#) : json(#"{"access_token":"gho_new"}"#)
            case "/user": return json(#"{"login":"me","name":"Me Myself"}"#)
            default: return json("{}", status: 404)
            }
        }
        let fetcher = StubFetcher()
        await fetcher.setSuccess(contributions: 4, for: "me")
        await fetcher.setSuccess(contributions: 9, for: "ada")
        await fetcher.setSuccess(contributions: 4, for: "lin")
        let credentials = InMemoryGitHubCredentialStore()
        let app = services(
            script: script,
            roster: { token in
                #expect(token == "gho_new")
                return GitHubRosterSnapshot(owner: "me", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["lin"]),
                    GitHubRosterSource(id: "org", title: "Org", members: ["ada"]),
                ], updatedAt: Date(timeIntervalSince1970: 0))
            },
            contributions: fetcher,
            credentials: credentials
        )

        await app.auth.signIn()

        #expect(app.auth.isSignedIn)
        #expect(app.auth.errorMessage == nil)
        #expect(credentials.read() == "gho_new")
        #expect(app.auth.username == "me")
        let entries = Ranking.order(
            competitors: app.store.visibleCompetitors,
            standings: app.store.standings(for: .daily),
            window: .daily
        )
        // ada leads; me and lin tie at 4, and me (the owner) comes first in roster order.
        #expect(entries.map(\.competitor.username) == ["ada", "me", "lin"])
        #expect(entries.map(\.rank) == [1, 2, 3])
        #expect(app.store.selfCompetitor?.username == "me")
    }

    @Test func codeThatExpiresWhileTheAppIsSuspendedIsReportedOnReturn() async {
        let script = Script()
        ConnectMockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/login/device/code": return json(deviceCodeJSON)
            default:
                // The first poll is pending; then the app is suspended in Safari for 20 minutes,
                // past the code's 15-minute lifetime, and polling resumes on return.
                script.tokenPolls += 1
                if script.tokenPolls == 1 { script.now = script.now.addingTimeInterval(20 * 60) }
                return json(#"{"error":"authorization_pending"}"#)
            }
        }
        let credentials = InMemoryGitHubCredentialStore()
        let app = services(script: script, credentials: credentials)
        await app.auth.signIn()

        #expect(app.auth.phase == .signedOut)
        #expect(app.auth.errorMessage == "The code expired. Try again.")
        #expect(credentials.read() == nil)
    }

    @Test func expiredCodeFromGitHubShowsTheExpiryMessage() async {
        let script = Script()
        ConnectMockURLProtocol.handler = { request in
            request.url?.path == "/login/device/code" ? json(deviceCodeJSON) : json(#"{"error":"expired_token"}"#)
        }
        let app = services(script: script)
        await app.auth.signIn()
        #expect(app.auth.phase == .signedOut)
        #expect(app.auth.errorMessage == "The code expired. Try again.")
    }

    @Test func deniedAccessShowsTheDenialMessage() async {
        let script = Script()
        ConnectMockURLProtocol.handler = { request in
            request.url?.path == "/login/device/code" ? json(deviceCodeJSON) : json(#"{"error":"access_denied"}"#)
        }
        let credentials = InMemoryGitHubCredentialStore()
        let app = services(script: script, credentials: credentials)
        await app.auth.signIn()
        #expect(app.auth.phase == .signedOut)
        #expect(app.auth.errorMessage == "The GitHub connection was declined.")
        #expect(credentials.read() == nil)
    }

    @Test func pollsDroppedWhileInTheBackgroundDoNotEndTheAttempt() async {
        let script = Script()
        ConnectMockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/login/device/code": return json(deviceCodeJSON)
            case "/login/oauth/access_token":
                script.tokenPolls += 1
                // iOS tears down in-flight requests when it suspends the app.
                if script.tokenPolls <= 3 { return .failure(URLError(.networkConnectionLost)) }
                return json(#"{"access_token":"gho_after_return"}"#)
            case "/user": return json(#"{"login":"me","name":null}"#)
            default: return json("{}", status: 404)
            }
        }
        let credentials = InMemoryGitHubCredentialStore()
        let app = services(script: script, credentials: credentials)
        await app.auth.signIn()
        #expect(app.auth.isSignedIn)
        #expect(credentials.read() == "gho_after_return")
    }

    @Test func disconnectDeletesTheTokenAndThisAccountsPeople() async throws {
        let script = Script()
        let credentials = InMemoryGitHubCredentialStore(token: "gho_x")
        let app = services(script: script, roster: { _ in
            GitHubRosterSnapshot(owner: "me", sources: [
                GitHubRosterSource(id: "following", title: "Following", members: ["ada"]),
            ], updatedAt: Date(timeIntervalSince1970: 0))
        }, credentials: credentials)
        await app.roster.refresh(force: true)
        #expect(app.store.competitors.map(\.username) == ["me", "ada"])

        app.auth.signOut()

        #expect(credentials.read() == nil)
        #expect(app.store.competitors.isEmpty)
        #expect(app.roster.snapshot == nil)
    }
}
