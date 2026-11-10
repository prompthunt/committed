import Foundation

enum ContributionsError: Error, Equatable {
    case userNotFound
    case network(String)
    case parseFailed(String)
}

protocol ContributionsFetching: Sendable {
    func standingCounts(
        for username: String,
        window: ContributionWindow,
        asOf reference: Date
    ) async -> Result<StandingCounts, ContributionsError>
}

/// Fetches a competitor's contributions for a window by scraping the public
/// `github.com/users/<name>/contributions` HTML (anonymously — no token, even when signed
/// in). The page carries a full year of per-day counts; the result keeps them, and its total for
/// `window` is worked out from them.
struct ContributionsClient: ContributionsFetching {
    private let session: URLSession
    private let baseURL: URL
    private let userAgent: String
    /// The zone the calendar is read in, asked at each fetch: the device's, unless a test pins it.
    private let timeZone: @Sendable () -> TimeZone

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://github.com")!,
        userAgent: String = "CommitStandings/0.1 (+https://github.com)",
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.timeZone = timeZone
    }

    func standingCounts(
        for username: String,
        window: ContributionWindow,
        asOf reference: Date
    ) async -> Result<StandingCounts, ContributionsError> {
        await history(for: username).map { history in
            StandingCounts(contributions: history.total(for: window, asOf: reference), history: history)
        }
    }

    /// The person's whole calendar (about 53 weeks), from one page.
    private func history(for username: String) async -> Result<ContributionHistory, ContributionsError> {
        let url = baseURL.appendingPathComponent("users/\(username)/contributions")
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        // Bound a single hung request so the task group cannot stall the
        // refresh cycle indefinitely if github.com stops responding.
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("Non-HTTP response"))
            }
            if http.statusCode == 404 {
                return .failure(.userNotFound)
            }
            guard (200...299).contains(http.statusCode) else {
                return .failure(.network("HTTP \(http.statusCode)"))
            }
            guard let html = String(data: data, encoding: .utf8) else {
                return .failure(.parseFailed("Non-UTF8 body"))
            }
            do {
                return .success(try ContributionsParser.parseHistory(html: html, timeZone: timeZone()))
            } catch let error as ContributionsError {
                return .failure(error)
            } catch {
                return .failure(.parseFailed(error.localizedDescription))
            }
        } catch let urlError as URLError {
            return .failure(.network(urlError.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
