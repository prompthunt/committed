import Testing
import Foundation
@testable import CommitStandingsiOS

/// Records requests to the relay and answers with a scripted status.
final class RelayStub: URLProtocol {
    struct Captured {
        let method: String
        let url: URL
        let authorization: String?
        let body: Data
    }

    nonisolated(unsafe) static var captured: [Captured] = []
    nonisolated(unsafe) static var status = 204
    nonisolated(unsafe) static var headers: [String: String] = [:]

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        Self.captured.append(Captured(method: request.httpMethod ?? "", url: request.url!,
                                      authorization: request.value(forHTTPHeaderField: "Authorization"), body: body))
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
                                       headerFields: Self.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// The app's side of the relay's device API (`relay/src/api.ts`), on the wire.
@Suite(.serialized)
struct RelayClientTests {
    private let installation = RelayInstallation(id: "3F2504E0-4F89-41D3-9A0C-0305E82C3301",
                                                 secret: String(repeating: "ab", count: 32))

    private func client(status: Int = 204, headers: [String: String] = [:]) -> HTTPLiveRankRelayClient {
        RelayStub.captured = []
        RelayStub.status = status
        RelayStub.headers = headers
        return HTTPLiveRankRelayClient(baseURL: URL(string: "https://relay.example.com")!, session: RelayStub.session)
    }

    @Test func registeringPutsExactlyTheContractFieldsWithTheBearerSecret() async throws {
        let client = client()

        try await client.register(RelayRegistration(
            login: "me", competitors: ["me", "alice"], window: "daily", timeZone: "America/Los_Angeles",
            environment: "sandbox", pushToStartToken: "0102"
        ), as: installation)

        let request = try #require(RelayStub.captured.only)
        #expect(request.method == "PUT")
        #expect(request.url.absoluteString == "https://relay.example.com/v1/installations/3F2504E0-4F89-41D3-9A0C-0305E82C3301")
        #expect(request.authorization == "Bearer \(installation.secret)")
        let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(Set(json.keys) == ["login", "competitors", "window", "timeZone", "environment", "pushToStartToken"],
                "the relay rejects any other field, so nothing else (like a GitHub token) can be sent")
        #expect(json["login"] as? String == "me")
        #expect(json["competitors"] as? [String] == ["me", "alice"])
        #expect(json["pushToStartToken"] as? String == "0102")
    }

    @Test func withoutAPushToStartTokenTheFieldIsLeftOut() async throws {
        let client = client()

        try await client.register(RelayRegistration(
            login: "me", competitors: ["me"], window: "weekly", timeZone: "UTC",
            environment: "production", pushToStartToken: nil
        ), as: installation)

        let request = try #require(RelayStub.captured.only)
        let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(Set(json.keys) == ["login", "competitors", "window", "timeZone", "environment"])
    }

    @Test func reportingAnActivityPutsItsIDAndToken() async throws {
        let client = client()

        try await client.reportActivity(id: "A1", pushToken: "c41d", as: installation)

        let request = try #require(RelayStub.captured.only)
        #expect(request.method == "PUT")
        #expect(request.url.path() == "/v1/installations/\(installation.id)/activity")
        let json = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: String])
        #expect(json == ["activityId": "A1", "pushToken": "c41d"])
    }

    @Test func unregisteringDeletes() async throws {
        let client = client()

        try await client.unregister(installation)

        let request = try #require(RelayStub.captured.only)
        #expect(request.method == "DELETE")
        #expect(request.url.path() == "/v1/installations/\(installation.id)")
        #expect(request.authorization == "Bearer \(installation.secret)")
    }

    @Test func errorStatusesAreReportedWithRetryAfter() async throws {
        let client = client(status: 429, headers: ["Retry-After": "90"])

        await #expect(throws: RelayClientError.rejected(status: 429, retryAfter: 90)) {
            try await client.unregister(installation)
        }
    }

    @Test func aNewInstallationHasAUUIDAndASecretTheRelayAccepts() {
        let installation = RelayInstallation.random()

        #expect(UUID(uuidString: installation.id) != nil)
        #expect((32...256).contains(installation.secret.count))
        #expect(installation != RelayInstallation.random())
    }
}

/// Which relay a build uses, from the `COMMITTED_RELAY_URL` / `COMMITTED_APNS_ENVIRONMENT`
/// build settings in the app's Info.plist.
struct RelayConfigurationTests {
    @Test func anEmptyOrMissingURLMeansNoRelay() {
        #expect(RelayConfiguration(info: nil) == nil)
        #expect(RelayConfiguration(info: [:]) == nil)
        #expect(RelayConfiguration(info: ["CommittedRelayURL": ""]) == nil)
        #expect(RelayConfiguration(info: ["CommittedRelayURL": "  "]) == nil)
        #expect(RelayConfiguration(info: ["CommittedRelayURL": "not a url"]) == nil)
    }

    @Test func aURLAndEnvironmentComeFromTheBuildSettings() throws {
        let staging = try #require(RelayConfiguration(info: [
            "CommittedRelayURL": "https://committed-relay.example.workers.dev",
            "CommittedAPNsEnvironment": "production",
        ]))
        #expect(staging.baseURL.absoluteString == "https://committed-relay.example.workers.dev")
        #expect(staging.environment == "production")

        let local = try #require(RelayConfiguration(info: ["CommittedRelayURL": "http://127.0.0.1:8787"]))
        #expect(local.environment == "sandbox", "development-signed builds get sandbox push tokens")
    }

    @Test func thisBuildsInfoPlistCarriesTheBuildSettings() {
        let app = Bundle.main.infoDictionary ?? [:]
        #expect(app["CommittedAPNsEnvironment"] as? String == "sandbox", "Debug builds use the APNs sandbox")
        #expect(app.keys.contains("CommittedRelayURL"))
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
