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
        return ContributionsClient(session: URLSession(configuration: config))
    }

    private func data(_ s: String) -> Data { Data(s.utf8) }

    private let reference = Date(timeIntervalSince1970: 1_717_000_000) // fixed for deterministic windows

    /// `reference`'s day, formatted the way the parser normalizes `data-date` (same calendar
    /// + current timezone). A legacy `data-count` cell on this date lands in the daily window.
    private var referenceDay: String {
        let cal = ContributionsParser.contributionCalendar()
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: cal.startOfDay(for: reference))
    }

    private func contributionsHTML(count: Int) -> Data {
        data(#"<table><td data-date="\#(referenceDay)" data-count="\#(count)"></td></table>"#)
    }

    @Test func standingCounts_success_returnsSummedContributions() async {
        MockURLProtocol.handler = { _ in (200, self.contributionsHTML(count: 5)) }
        let result = await makeClient().standingCounts(for: "addisonk", window: .daily, asOf: reference)
        #expect(result == .success(StandingCounts(contributions: 5)))
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
