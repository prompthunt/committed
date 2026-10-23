import Foundation
import Observation

enum CompetitorMutationError: Error, Equatable {
    case selfAlreadyExists
    case selfRequiredFirst
    case duplicateUsername
    case invalidUsername
    case cannotRemoveSelf
    case notFound

    /// User-facing message safe to surface in inline error UI.
    var userMessage: String {
        switch self {
        case .selfAlreadyExists: return "You're already in the list."
        case .selfRequiredFirst: return "Add yourself first."
        case .duplicateUsername: return "Already on the list."
        case .invalidUsername:   return "That doesn't look like a GitHub username."
        case .cannotRemoveSelf:  return "You can't remove yourself."
        case .notFound:          return "Not found."
        }
    }
}

extension Error {
    /// Convenience for views: returns `CompetitorMutationError.userMessage`
    /// when applicable, otherwise falls back to `localizedDescription`.
    var userFacingMessage: String {
        (self as? CompetitorMutationError)?.userMessage ?? localizedDescription
    }
}

@Observable
@MainActor
final class StandingsStore {
    private(set) var competitors: [Competitor]
    private(set) var standings: [String: Standing] = [:]
    private(set) var lastUpdated: Date?
    var selectedWindow: ContributionWindow = .daily
    private(set) var visibilityRevision = 0

    private let persistence: CompetitorPersistence
    private let snapshotPersistence: StandingsSnapshotPersistence
    private let hiddenPeoplePersistence: any HiddenPeoplePersistence
    private var hiddenByAccount: [String: Set<String>]

    init(
        persistence: CompetitorPersistence = UserDefaultsCompetitorPersistence(),
        // Durable snapshot is opt-in (production passes a UserDefaults-backed instance);
        // defaults to in-memory so test suites and previews stay isolated.
        snapshotPersistence: StandingsSnapshotPersistence = InMemoryStandingsSnapshotPersistence(),
        hiddenPeoplePersistence: any HiddenPeoplePersistence = InMemoryHiddenPeoplePersistence()
    ) {
        self.persistence = persistence
        self.snapshotPersistence = snapshotPersistence
        self.hiddenPeoplePersistence = hiddenPeoplePersistence
        self.hiddenByAccount = hiddenPeoplePersistence.load()
        self.competitors = persistence.load()
        // Restore the last loaded standings so the board renders immediately. State is
        // forced to `.loaded` (we're not mid-fetch at launch); stale entries for people
        // no longer tracked are dropped.
        let known = Set(competitors.map(\.username))
        for var snapshot in snapshotPersistence.load() where known.contains(snapshot.username) {
            snapshot.state = .loaded
            standings[key(snapshot.username, snapshot.window)] = snapshot
        }
    }

    /// Wipe all local state — competitors (including self) and cached standings — and
    /// persist the empty result. Used by "Reset…" to return to a fresh first-run state
    /// (paired with sign-out, which clears the token).
    func reset() {
        competitors = []
        standings = [:]
        lastUpdated = nil
        persist()
        snapshotPersistence.save([])
    }

    var selfCompetitor: Competitor? {
        competitors.first(where: { $0.isSelf })
    }

    var rivals: [Competitor] {
        visibleCompetitors.filter { !$0.isSelf }
    }

    var hasSelf: Bool { selfCompetitor != nil }

    /// Keep the complete GitHub roster for People; all ranking consumers use this projection.
    var visibleCompetitors: [Competitor] {
        guard let owner = selfCompetitor?.username else { return competitors }
        let hidden = hiddenByAccount[owner] ?? []
        return competitors.filter { $0.isSelf || !hidden.contains($0.username) }
    }

    func isHidden(_ rawUsername: String) -> Bool {
        guard let owner = selfCompetitor?.username,
              let username = UsernameNormalization.normalize(rawUsername), username != owner else { return false }
        return hiddenByAccount[owner]?.contains(username) == true
    }

    /// Visibility is local to this GitHub account and survives roster refreshes, temporary
    /// departures, and sign-out. Hiding never changes GitHub membership or following.
    func setHidden(_ hidden: Bool, username rawUsername: String) {
        guard let owner = selfCompetitor?.username,
              let username = UsernameNormalization.normalize(rawUsername), username != owner,
              competitors.contains(where: { $0.username == username }), isHidden(username) != hidden else { return }
        if hidden {
            hiddenByAccount[owner, default: []].insert(username)
        } else {
            hiddenByAccount[owner]?.remove(username)
        }
        visibilityRevision += 1
        hiddenPeoplePersistence.save(hiddenByAccount)
    }

    /// Reconcile the automatic roster, retaining row identities and cached counts for people
    /// who remain. Sorting makes tied ranks deterministic across devices and refreshes.
    func replaceRoster(owner: String, members: [String]) {
        guard let owner = UsernameNormalization.normalize(owner) else { return }
        let usernames = [owner] + Set(members.compactMap(UsernameNormalization.normalize))
            .subtracting([owner]).sorted()
        let existing = Dictionary(competitors.map { ($0.username, $0) }, uniquingKeysWith: { first, _ in first })
        competitors = usernames.map { username in
            var person = existing[username] ?? Competitor(username: username, isSelf: username == owner)
            person.isSelf = username == owner
            return person
        }
        let known = Set(usernames)
        standings = standings.filter { known.contains($0.value.username) }
        persist()
        persistSnapshot()
    }

    // MARK: - Mutations

    @discardableResult
    func addSelf(username rawUsername: String) throws -> Competitor {
        guard let username = UsernameNormalization.normalize(rawUsername) else {
            throw CompetitorMutationError.invalidUsername
        }
        if hasSelf {
            throw CompetitorMutationError.selfAlreadyExists
        }
        if competitors.contains(where: { $0.username == username }) {
            throw CompetitorMutationError.duplicateUsername
        }
        let entry = Competitor(username: username, isSelf: true)
        competitors.insert(entry, at: 0)
        persist()
        return entry
    }

    @discardableResult
    func addRival(username rawUsername: String) throws -> Competitor {
        guard let username = UsernameNormalization.normalize(rawUsername) else {
            throw CompetitorMutationError.invalidUsername
        }
        guard hasSelf else {
            throw CompetitorMutationError.selfRequiredFirst
        }
        if competitors.contains(where: { $0.username == username }) {
            throw CompetitorMutationError.duplicateUsername
        }
        let entry = Competitor(username: username, isSelf: false)
        competitors.append(entry)
        persist()
        return entry
    }

    func remove(id: UUID) throws {
        guard let idx = competitors.firstIndex(where: { $0.id == id }) else {
            throw CompetitorMutationError.notFound
        }
        if competitors[idx].isSelf {
            throw CompetitorMutationError.cannotRemoveSelf
        }
        let removed = competitors.remove(at: idx)
        removeStandings(for: removed.username)
        persist()
    }

    @discardableResult
    func rename(id: UUID, to rawUsername: String) throws -> Competitor {
        guard let username = UsernameNormalization.normalize(rawUsername) else {
            throw CompetitorMutationError.invalidUsername
        }
        guard let idx = competitors.firstIndex(where: { $0.id == id }) else {
            throw CompetitorMutationError.notFound
        }
        let existing = competitors[idx]
        if existing.username == username {
            return existing
        }
        if competitors.contains(where: { $0.username == username }) {
            throw CompetitorMutationError.duplicateUsername
        }
        removeStandings(for: existing.username)
        competitors[idx].username = username
        persist()
        return competitors[idx]
    }

    // MARK: - Standings updates

    /// Standings are cached per (username, window) so switching windows retains each
    /// window's data — flipping Daily → Weekly → Daily shows the cached Daily numbers
    /// instantly instead of blanking and refetching.
    private func key(_ username: String, _ window: ContributionWindow) -> String {
        "\(username)\u{1}\(window.rawValue)"
    }

    /// The cached standing for a competitor in a specific window, if any.
    func standing(for username: String, window: ContributionWindow) -> Standing? {
        standings[key(username, window)]
    }

    /// All standings for a window, keyed by username (for ranking/label lookups).
    func standings(for window: ContributionWindow) -> [String: Standing] {
        var result: [String: Standing] = [:]
        for value in standings.values where value.window == window {
            result[value.username] = value
        }
        return result
    }

    private func removeStandings(for username: String) {
        for window in ContributionWindow.allCases {
            standings.removeValue(forKey: key(username, window))
        }
    }

    func updateStanding(_ standing: Standing) {
        guard competitors.contains(where: { $0.username == standing.username }) else {
            return // dropped competitor; ignore stale result
        }
        standings[key(standing.username, standing.window)] = standing
        persistSnapshot()
    }

    /// Persist only standings that carry real data (a non-`.distantPast` timestamp), so
    /// a relaunch restores values — never an empty placeholder mid-first-load.
    private func persistSnapshot() {
        snapshotPersistence.save(standings.values.filter { $0.lastUpdated != .distantPast })
    }

    func markRefreshComplete(at date: Date) {
        lastUpdated = date
    }

    func markLoading(username: String, window: ContributionWindow) {
        let k = key(username, window)
        if let existing = standings[k] {
            // Keep the cached numbers; just flag the in-flight refresh.
            var copy = existing
            copy.state = .loading
            standings[k] = copy
        } else {
            standings[k] = Standing(
                username: username,
                contributions: 0,
                window: window,
                lastUpdated: .distantPast,
                state: .loading
            )
        }
    }

    private func persist() {
        persistence.save(competitors)
    }
}
