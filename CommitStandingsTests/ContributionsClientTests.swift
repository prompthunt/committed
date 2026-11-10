import Testing
import Foundation
@testable import CommitStandings

/// URLProtocol stub: routes each request through a test-provided handler that
/// returns an (HTTP status, body) pair. The suite is serialized so the static
/// handler is never shared across concurrent tests.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
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
struct ContributionsClientTests {

    private func makeClient() -> ContributionsClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return ContributionsClient(session: URLSession(configuration: config), timeZone: { Self.zone })
    }

    /// The client reads in an injected zone, so these tests don't depend on the machine's.
    private static let zone = TimeZone(identifier: "America/Los_Angeles")!

    private func data(_ s: String) -> Data { Data(s.utf8) }

    private let reference = Date(timeIntervalSince1970: 1_717_000_000) // fixed for deterministic windows

    /// `reference`'s day in Los Angeles (2024-05-29 09:26 PDT). A legacy `data-count` cell on
    /// this date lands in the daily window.
    private let referenceDay = "2024-05-29"

    private func contributionsHTML(count: Int) -> Data {
        data(#"<table><td data-date="\#(referenceDay)" data-count="\#(count)"></td></table>"#)
    }

    @Test func standingCounts_success_returnsSummedContributions() async throws {
        MockURLProtocol.handler = { _ in (200, self.contributionsHTML(count: 5)) }
        let result = await makeClient().standingCounts(for: "addisonk", window: .daily, asOf: reference)
        #expect(try result.get().contributions == 5)
    }

    /// One page carries the whole calendar: the result keeps every parsed day and the zone it was
    /// read in, and the Window total is worked out from them.
    @Test func standingCounts_success_carriesTheDaysAndTheirTimeZone() async throws {
        MockURLProtocol.handler = { _ in
            (200, self.data(#"<td data-date="2024-05-22" data-count="100"></td><td data-date="2024-05-24" data-count="2"></td><td data-date="2024-05-29" data-count="3"></td>"#))
        }
        let counts = try await makeClient().standingCounts(for: "addisonk", window: .weekly, asOf: reference).get()
        let history = try #require(counts.history)
        #expect(history.days == ["2024-05-22": 100, "2024-05-24": 2, "2024-05-29": 3])
        #expect(history.timeZone == Self.zone)
        #expect(counts.contributions == 5)
        #expect(history.total(for: .weekly, asOf: reference) == 5)
    }

    @Test func standingCounts_userNotFound_returnsFailure() async {
        MockURLProtocol.handler = { _ in (404, Data()) }
        let result = await makeClient().standingCounts(for: "ghost", window: .weekly, asOf: reference)
        #expect(result == .failure(.userNotFound))
    }

    @Test func standingCounts_rateLimited_returnsNetworkFailure() async {
        MockURLProtocol.handler = { _ in (403, self.data("rate limited")) }
        let result = await makeClient().standingCounts(for: "x", window: .daily, asOf: reference)
        if case .failure(.network) = result { } else { Issue.record("expected network failure on 403") }
    }

    @Test func standingCounts_malformedHTML_returnsParseFailure() async {
        MockURLProtocol.handler = { _ in (200, self.data("<html>no calendar here</html>")) }
        let result = await makeClient().standingCounts(for: "x", window: .daily, asOf: reference)
        if case .failure(.parseFailed) = result { } else { Issue.record("expected parseFailed on calendar-less HTML") }
    }

    @Test func contributionsRequest_isAnonymous_noAuthHeader() async {
        var hadAuth = true
        MockURLProtocol.handler = { req in
            hadAuth = req.value(forHTTPHeaderField: "Authorization") != nil
            return (200, self.contributionsHTML(count: 0))
        }
        _ = await makeClient().standingCounts(for: "addisonk", window: .daily, asOf: reference)
        #expect(hadAuth == false, "the contributions scrape must stay anonymous")
    }
}
