import Foundation
import Observation

struct GitHubRosterSource: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let members: [String]
    var isFollowing: Bool { id == "following" }
}

struct GitHubRosterSnapshot: Codable, Equatable, Sendable {
    let owner: String
    let sources: [GitHubRosterSource]
    let updatedAt: Date

    func usernames(in filter: PeopleSourceFilter) -> Set<String> {
        let selectedSources = sources.filter { source in
            switch filter {
            case .all: return true
            case .following: return source.isFollowing
            case .organizations: return !source.isFollowing
            }
        }
        var result = Set(selectedSources.flatMap(\.members).compactMap(UsernameNormalization.normalize))
        if filter == .all { result.insert(owner) }
        return result
    }
}

enum PeopleSourceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case following = "Following"
    case organizations = "Organizations"
    var id: Self { self }
}

protocol GitHubRosterPersistence: Sendable {
    func load() -> GitHubRosterSnapshot?
    func save(_ snapshot: GitHubRosterSnapshot?)
}

final class UserDefaultsGitHubRosterPersistence: GitHubRosterPersistence, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "githubRoster.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> GitHubRosterSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GitHubRosterSnapshot.self, from: data)
    }
    func save(_ snapshot: GitHubRosterSnapshot?) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
}

/// The roster is replaced only after ALL sources load successfully. Offline, permission,
/// cancellation, and pagination failures preserve the last complete list.
@Observable
@MainActor
final class GitHubRoster {
    private(set) var snapshot: GitHubRosterSnapshot?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private let store: StandingsStore
    private let credentials: any GitHubCredentialStoring
    private let persistence: (any GitHubRosterPersistence)?
    private let legacyBackup: (any CompetitorPersistence)?
    private let fetch: @Sendable (String) async throws -> GitHubRosterSnapshot
    private let now: @Sendable () -> Date
    private var generation = UUID()
    private var lastAttempt: Date?

    init(store: StandingsStore, credentials: any GitHubCredentialStoring,
         persistence: (any GitHubRosterPersistence)? = nil,
         legacyBackup: (any CompetitorPersistence)? = nil,
         now: @escaping @Sendable () -> Date = { Date() },
         fetch: @escaping @Sendable (String) async throws -> GitHubRosterSnapshot = { try await GitHubAccountClient(token: $0).roster() }) {
        self.store = store
        self.credentials = credentials
        self.persistence = persistence
        self.legacyBackup = legacyBackup
        self.now = now
        self.fetch = fetch
        snapshot = persistence?.load()
        if credentials.read() != nil, let snapshot {
            store.replaceRoster(owner: snapshot.owner, members: snapshot.sources.flatMap(\.members))
        }
    }

    func refresh(force: Bool = false) async {
        guard !isRefreshing, let token = credentials.read() else { return }
        // Avoid hammering GitHub on every menu open, including after failures.
        if !force, let lastAttempt, now().timeIntervalSince(lastAttempt) < 900 { return }
        isRefreshing = true
        lastAttempt = now()
        let requestGeneration = generation
        defer { if generation == requestGeneration { isRefreshing = false } }
        do {
            let result = try await fetch(token)
            try Task.checkCancellation()
            guard generation == requestGeneration, credentials.read() == token else { return }
            if snapshot == nil, let legacyBackup, legacyBackup.load().isEmpty {
                legacyBackup.save(store.competitors)
            }
            // Do not carry cached counts or identities between different accounts.
            if let previousOwner = store.selfCompetitor?.username, previousOwner != result.owner { store.reset() }
            store.replaceRoster(owner: result.owner, members: result.sources.flatMap(\.members))
            snapshot = result
            persistence?.save(result)
            errorMessage = nil
        } catch is CancellationError {
            // Dismissing a view can cancel its refresh. Permit the next open to retry.
            if generation == requestGeneration { lastAttempt = nil }
        } catch {
            if Task.isCancelled {
                if generation == requestGeneration { lastAttempt = nil }
                return
            }
            guard generation == requestGeneration, credentials.read() == token else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Explicit sign-out clears this account's cached people and invalidates in-flight work.
    func disconnect() {
        generation = UUID()
        snapshot = nil
        persistence?.save(nil)
        store.reset()
        errorMessage = nil
        lastAttempt = nil
        isRefreshing = false
    }
}
