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
/// in). The page carries a full year of per-day counts, so any window is summed locally.
struct ContributionsClient: ContributionsFetching {
    private let session: URLSession
    private let baseURL: URL
    private let userAgent: String

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://github.com")!,
        userAgent: String = "CommitStandings/0.1 (+https://github.com)"
    ) {
        self.session = session
        self.baseURL = baseURL
        self.userAgent = userAgent
    }

    func standingCounts(
        for username: String,
        window: ContributionWindow,
        asOf reference: Date
    ) async -> Result<StandingCounts, ContributionsError> {
        await contributionCount(for: username, window: window, asOf: reference)
            .map { StandingCounts(contributions: $0) }
    }

    private func contributionCount(
        for username: String,
        window: ContributionWindow,
        asOf reference: Date
    ) async -> Result<Int, ContributionsError> {
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
                let days = try ContributionsParser.parseDays(html: html)
                return .success(ContributionsParser.sum(days: days, window: window, asOf: reference))
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
