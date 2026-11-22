#if DEBUG
import Foundation

/// A real board saved from public data, so agents can run the app and render screenshots on the
/// owner's real board without a GitHub token (Debug builds only).
///
/// Only the roster needs the owner: GitHub's people and organization calls need a token, so the
/// owner keeps a roster file (`BoardRoster`) outside the repo. The counts don't: they come from
/// each person's public contribution calendar, read anonymously by the app's own
/// `ContributionsClient`, as the app always reads them. `RealBoardTests` turns a roster into a
/// snapshot; the screenshot fixture (`-ScreenshotBoardFile <path>`) and the App Store render then
/// run the real app on it offline. Snapshots and their renders stay outside the repo.
///
/// Nothing in it is private: logins and public contribution counts. The board is still the
/// owner's choice of people, so it's never committed.
struct BoardSnapshot: Codable, Equatable, Sendable {
    /// You.
    var owner: String
    var ownerName: String?
    /// Everyone else on the board, in the roster's order.
    var people: [String]
    /// People hidden from the board, as hidden on the phone.
    var hidden: [String]
    /// Rivals pinned to Your rivals, at most three.
    var pins: [String]
    /// When the calendars were read. The app's clock is set to it, so today is the day they were
    /// read and the counts read as they did then.
    var fetchedAt: Date
    /// The zone the calendars were read in (IANA).
    var timeZone: String
    /// Each person's calendar, as GitHub's contribution graph has it: login → "YYYY-MM-DD" → count.
    /// Someone whose calendar couldn't be read is missing, and the board shows them as not loaded.
    var calendars: [String: [String: Int]]

    /// Everyone on the board, you first.
    var everyone: [String] { [owner] + people.filter { $0 != owner } }

    func history(for login: String) -> ContributionHistory? {
        guard let days = calendars[login] else { return nil }
        return ContributionHistory(days: days, timeZone: TimeZone(identifier: timeZone) ?? .current)
    }

    static func load(from url: URL) throws -> BoardSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BoardSnapshot.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// Who's on the owner's board: the file the owner keeps outside the repo (for example
/// `~/.config/committed/board.json`), the one thing a snapshot needs from them.
///
///     { "owner": "addisonk", "people": ["odile-m", "ezra-q"], "hidden": [], "pins": ["ezra-q"] }
struct BoardRoster: Codable, Equatable, Sendable {
    var owner: String
    var ownerName: String?
    var people: [String]
    var hidden: [String]?
    var pins: [String]?

    static func load(from url: URL) throws -> BoardRoster {
        try JSONDecoder().decode(BoardRoster.self, from: Data(contentsOf: url))
    }

    /// Reads each person's public calendar with `contributions` (the app's anonymous
    /// `ContributionsClient` by default), one at a time, and saves them as a snapshot. Anyone
    /// without one (an organization you follow, a renamed account) is left out of `calendars`.
    func snapshot(
        contributions: any ContributionsFetching = ContributionsClient(),
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) async -> BoardSnapshot {
        let owner = owner.lowercased()
        let people = people.map { $0.lowercased() }.filter { $0 != owner }
        var calendars: [String: [String: Int]] = [:]
        for login in [owner] + people {
            // One retry: a calendar that times out once usually loads the second time.
            for _ in 0..<2 {
                if case .success(let counts) = await contributions.standingCounts(for: login, window: .daily, asOf: now),
                   let history = counts.history {
                    calendars[login] = history.days
                    break
                }
            }
        }
        return BoardSnapshot(
            owner: owner, ownerName: ownerName, people: people,
            hidden: (hidden ?? []).map { $0.lowercased() },
            pins: Array((pins ?? []).map { $0.lowercased() }.prefix(3)),
            fetchedAt: now, timeZone: timeZone.identifier, calendars: calendars
        )
    }
}

/// The app's services on a `BoardSnapshot`: `CommittedServices` with the snapshot's people and
/// calendars, held in memory, nothing sent over the network. Like `SampleServices`, everything
/// above the data is real (`RefreshCoordinator`, `Ranking`, every view), and it's connected, so
/// the person view's Challenge works.
@MainActor
enum SnapshotServices {
    static func make(_ snapshot: BoardSnapshot, now: @escaping @Sendable () -> Date) -> CommittedServices {
        SnapshotGitHub.profile = Data(
            (try? JSONEncoder().encode(Profile(login: snapshot.owner, name: snapshot.ownerName))) ?? Data()
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SnapshotGitHub.self]
        let session = URLSession(configuration: config)
        let people = snapshot.people
        let owner = snapshot.owner
        let updatedAt = snapshot.fetchedAt
        return CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: "snapshot"),
            contributions: SnapshotContributions(snapshot: snapshot),
            gitHubAuth: GitHubAuth(clientID: "snapshot", session: session),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: owner, sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: people),
                ], updatedAt: updatedAt)
            },
            now: now
        )
    }

    private struct Profile: Encodable {
        let login: String
        let name: String?
    }

    /// The snapshot's calendars, the same on every fetch: Today shows no movement, as nothing
    /// was seen to move.
    private struct SnapshotContributions: ContributionsFetching {
        let snapshot: BoardSnapshot

        func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date)
            async -> Result<StandingCounts, ContributionsError> {
            guard let history = snapshot.history(for: username) else { return .failure(.network("offline")) }
            return .success(StandingCounts(history: history, window: window, asOf: reference))
        }
    }

    /// Answers GitHub's `/user` with the snapshot's owner, in process, and fails everything else
    /// as if offline.
    private final class SnapshotGitHub: URLProtocol {
        nonisolated(unsafe) static var profile = Data()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url, url.host == "api.github.com", url.path == "/user",
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.profile)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
#endif
