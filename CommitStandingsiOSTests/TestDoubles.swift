import Testing
import Foundation
@testable import CommitStandingsiOS

/// Every suite that drives `FakeGitHub` nests here: its script is static, so they must not
/// run in parallel with each other.
@Suite(.serialized)
enum FakeGitHubSuites {}

/// A scripted github.com + api.github.com behind a URLProtocol, so the iPhone app's real
/// device-flow and account clients run end to end without the network. Suites using it nest
/// in `FakeGitHubSuites`.
final class FakeGitHub: URLProtocol {
    enum Poll { case pending, slowDown, token(String), expired, denied }

    struct Script {
        var userCode = "WDJB-MJHT"
        var polls: [Poll] = []
        var login = "me"
        var name: String? = "Morgan Example"
        var following: [String] = []
        var organizations: [String: [String]] = [:]
        var failRoster = false
    }

    nonisolated(unsafe) static var script = Script()
    nonisolated(unsafe) static var deviceCodeBodies: [String] = []
    nonisolated(unsafe) static var pollCount = 0
    nonisolated(unsafe) static var rosterRequests = 0

    static func reset(_ script: Script) {
        self.script = script
        deviceCodeBodies = []
        pollCount = 0
        rosterRequests = 0
    }

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeGitHub.self]
        return URLSession(configuration: config)
    }

    /// The `scope` form field from the device-code request, decoded.
    static var requestedScope: String? {
        guard let body = deviceCodeBodies.last else { return nil }
        let field = body.split(separator: "&").first { $0.hasPrefix("scope=") }
        return field.map { String($0.dropFirst("scope=".count)).removingPercentEncoding ?? "" }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (status, body) = Self.respond(to: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func respond(to request: URLRequest) -> (Int, String) {
        let path = request.url?.path ?? ""
        switch path {
        case "/login/device/code":
            deviceCodeBodies.append(String(decoding: bodyData(request), as: UTF8.self))
            return (200, #"{"device_code":"dc","user_code":"\#(script.userCode)","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#)
        case "/login/oauth/access_token":
            let poll = pollCount < script.polls.count ? script.polls[pollCount] : .pending
            pollCount += 1
            switch poll {
            case .pending: return (200, #"{"error":"authorization_pending"}"#)
            case .slowDown: return (200, #"{"error":"slow_down"}"#)
            case .expired: return (200, #"{"error":"expired_token"}"#)
            case .denied: return (200, #"{"error":"access_denied"}"#)
            case .token(let token): return (200, #"{"access_token":"\#(token)","token_type":"bearer"}"#)
            }
        case "/user":
            let name = script.name.map { #""\#($0)""# } ?? "null"
            return (200, #"{"login":"\#(script.login)","name":\#(name)}"#)
        case "/user/orgs":
            rosterRequests += 1
            if script.failRoster { return (503, "{}") }
            return (200, logins(script.organizations.keys.sorted()))
        case "/user/following":
            return (200, logins(script.following))
        default:
            if path.hasPrefix("/orgs/"), path.hasSuffix("/members") {
                let org = path.dropFirst("/orgs/".count).dropLast("/members".count)
                return (200, logins(script.organizations[String(org)] ?? []))
            }
            return (404, "{}")
        }
    }

    private static func logins(_ names: [String]) -> String {
        "[" + names.map { #"{"login":"\#($0)"}"# }.joined(separator: ",") + "]"
    }

    private static func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Contribution counts per username, with a call log so tests can see what was fetched.
actor StubContributions: ContributionsFetching {
    private var counts: [String: Int]
    private(set) var calls: [(username: String, window: ContributionWindow)] = []

    init(_ counts: [String: Int] = [:]) { self.counts = counts }

    func set(_ username: String, _ contributions: Int) { counts[username] = contributions }
    func callCount() -> Int { calls.count }

    func standingCounts(
        for username: String,
        window: ContributionWindow,
        asOf reference: Date
    ) async -> Result<StandingCounts, ContributionsError> {
        calls.append((username, window))
        guard let count = counts[username] else { return .failure(.network("offline")) }
        return .success(StandingCounts(contributions: count))
    }
}

/// A clock tests can move, e.g. past a device code's expiry while the app is "suspended".
final class TestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) { self.date = date }
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

extension AppDependencies {
    /// In-memory everything, GitHub faked by `FakeGitHub`, no real waiting between polls.
    static func testing(
        contributions: StubContributions,
        credentials: InMemoryGitHubCredentialStore = InMemoryGitHubCredentialStore(),
        clock: TestClock = TestClock(),
        authSleep: (@Sendable (UInt64) async -> Void)? = nil
    ) -> AppDependencies {
        AppDependencies(
            credentials: credentials,
            gitHubSession: FakeGitHub.session,
            contributions: contributions,
            competitorPersistence: InMemoryCompetitorPersistence(),
            snapshotPersistence: InMemoryStandingsSnapshotPersistence(),
            hiddenPeoplePersistence: InMemoryHiddenPeoplePersistence(),
            rosterPersistence: nil,
            refreshInterval: 99_999,
            authSleep: authSleep ?? { _ in },
            now: { clock.date },
            // A throwaway store, so tests never flip the real app's notification toggle.
            notificationDefaults: UserDefaults(suiteName: "CommitStandingsiOSTests.\(UUID().uuidString)")!,
            notificationCenter: FakeNotificationCenter()
        )
    }
}
