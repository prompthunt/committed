import Testing
import Foundation
@testable import CommitStandings

/// Separate URLProtocol from the ContributionsClient tests so the two serialized
/// suites never share a static handler.
final class AuthMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = AuthMockURLProtocol.handler else {
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

@Suite(.serialized)
struct GitHubAuthTests {

    /// Mutable call counter for staged poll responses (safe within the serialized suite).
    final class Counter: @unchecked Sendable { var n = 0 }

    private func makeAuth(
        now: (@Sendable () -> Date)? = nil,
        _ handler: @escaping (URLRequest) -> (Int, Data)
    ) -> GitHubAuth {
        AuthMockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthMockURLProtocol.self]
        return GitHubAuth(
            clientID: "test-client",
            session: URLSession(configuration: config),
            sleep: { _ in },
            now: now ?? { Date() }
        )
    }

    private func data(_ s: String) -> Data { Data(s.utf8) }

    /// Regression guard: the app must request a public-only scope. `repo` would grant
    /// read+write to all private repos (the scary consent screen we deliberately removed).
    @Test func requestedScopeIsPublicOnlyNoRepo() {
        #expect(GitHubConfig.scope == "read:org read:user")
        let tokens = Set(GitHubConfig.scope.split(separator: " ").map(String.init))
        #expect(tokens == ["read:org", "read:user"])
        #expect(!tokens.contains("repo"))
    }

    @Test func requestDeviceCode_parsesSnakeCaseResponse() async {
        let auth = makeAuth { _ in
            (200, self.data(#"{"device_code":"d1","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#))
        }
        let result = await auth.requestDeviceCode()
        guard case .success(let code) = result else { Issue.record("expected success"); return }
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.verificationUri == "https://github.com/login/device")
        #expect(code.deviceCode == "d1")
        #expect(code.interval == 5)
    }

    @Test func pollForToken_pendingThenSuccess() async {
        let counter = Counter()
        let auth = makeAuth { _ in
            counter.n += 1
            return counter.n == 1
                ? (200, self.data(#"{"error":"authorization_pending"}"#))
                : (200, self.data(#"{"access_token":"gho_token"}"#))
        }
        let result = await auth.pollForToken(deviceCode: "d1", interval: 1, expiresIn: 900)
        #expect(result == .success("gho_token"))
    }

    @Test func pollForToken_slowDownThenSuccess() async {
        let counter = Counter()
        let auth = makeAuth { _ in
            counter.n += 1
            return counter.n == 1
                ? (200, self.data(#"{"error":"slow_down"}"#))
                : (200, self.data(#"{"access_token":"gho_t2"}"#))
        }
        let result = await auth.pollForToken(deviceCode: "d1", interval: 1, expiresIn: 900)
        #expect(result == .success("gho_t2"))
    }

    @Test func pollForToken_expiredToken_returnsExpired() async {
        let auth = makeAuth { _ in (200, self.data(#"{"error":"expired_token"}"#)) }
        let result = await auth.pollForToken(deviceCode: "d1", interval: 1, expiresIn: 900)
        #expect(result == .failure(.expired))
    }

    @Test func pollForToken_accessDenied_returnsDenied() async {
        let auth = makeAuth { _ in (200, self.data(#"{"error":"access_denied"}"#)) }
        let result = await auth.pollForToken(deviceCode: "d1", interval: 1, expiresIn: 900)
        #expect(result == .failure(.denied))
    }

    @Test func pollForToken_neverApproved_expiresViaDeadline() async {
        // Clock advances 5s per call; with expiresIn=10 the deadline is crossed after
        // a couple iterations even though the server returns authorization_pending forever.
        let clock = Counter()
        let now: @Sendable () -> Date = {
            let t = Date(timeIntervalSince1970: 1_000_000 + Double(clock.n) * 5)
            clock.n += 1
            return t
        }
        let auth = makeAuth(now: now) { _ in (200, self.data(#"{"error":"authorization_pending"}"#)) }
        let result = await auth.pollForToken(deviceCode: "d1", interval: 1, expiresIn: 10)
        #expect(result == .failure(.expired))
    }

    @Test func pollForToken_unknownError_returnsUnexpected() async {
        let auth = makeAuth { _ in (200, self.data(#"{"error":"something_weird"}"#)) }
        let result = await auth.pollForToken(deviceCode: "d1", interval: 1, expiresIn: 900)
        #expect(result == .failure(.unexpected("something_weird")))
    }
}
