import Foundation

// The Committed relay (phase 2): a push service that keeps Live rank current while the app is
// closed. The app registers public logins only (yours and the visible ones on your board),
// never the GitHub token. Device API: `relay/src/api.ts` and `relay/README.md`.

/// `PUT /v1/installations/{id}`. Encoded exactly as the relay expects: it rejects unknown keys,
/// and an absent `pushToStartToken` means iOS hasn't issued one.
struct RelayRegistration: Codable, Equatable, Sendable {
    var login: String
    /// The visible board in board order, you included (order breaks ties). At most 1,000.
    var competitors: [String]
    /// `ContributionWindow` raw value.
    var window: String
    /// IANA time zone: Today is summed for this zone's calendar day.
    var timeZone: String
    /// "sandbox" (development-signed builds) or "production" (TestFlight and the App Store).
    var environment: String
    /// Hex, or nil until iOS issues one.
    var pushToStartToken: String?

    static let maxCompetitors = 1000
}

/// This iPhone's identity at the relay: a random install ID and the secret that authorizes
/// every write (the relay keeps only its hash). Generated once, kept in the Keychain.
struct RelayInstallation: Codable, Equatable, Sendable {
    var id: String
    var secret: String

    static func random() -> RelayInstallation {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return RelayInstallation(id: UUID().uuidString, secret: bytes.map { String(format: "%02x", $0) }.joined())
    }
}

enum RelayClientError: Error, Equatable {
    /// The relay answered with an error status (400, 401, 404, 409, 429...).
    case rejected(status: Int, retryAfter: TimeInterval? = nil)
    /// No answer: offline, timed out, or no relay listening.
    case unreachable(String)
}

/// The relay's device API. `HTTPLiveRankRelayClient` is the real one; tests use a fake.
protocol LiveRankRelayClient: Sendable {
    func register(_ registration: RelayRegistration, as installation: RelayInstallation) async throws
    func reportActivity(id: String, pushToken: String, as installation: RelayInstallation) async throws
    func unregister(_ installation: RelayInstallation) async throws
}

/// What the relay last accepted from this iPhone, so unchanged state isn't re-sent (the relay
/// allows 30 writes per 10 minutes) and a relaunch knows whether an unregister is still owed.
struct RelaySentState: Codable, Equatable, Sendable {
    struct Activity: Codable, Equatable, Sendable {
        var id: String
        var pushToken: String
    }

    var registration: RelayRegistration?
    var activity: Activity?
}

protocol LiveRankRelayStore: Sendable {
    func loadInstallation() -> RelayInstallation?
    func saveInstallation(_ installation: RelayInstallation?)
    func loadSent() -> RelaySentState
    func saveSent(_ sent: RelaySentState)
}

/// Everything Live rank needs to use a relay. Nil in `AppDependencies` means no relay is
/// configured, and Live rank stays on-device only (phase 1).
struct LiveRankRelayDependencies {
    var client: any LiveRankRelayClient
    var store: any LiveRankRelayStore
    /// "sandbox" or "production", matching the APNs environment of this build's push tokens.
    var environment: String
}

/// The part of a registration that comes from the board; the relay adds the token and environment.
struct RelayBoard: Equatable, Sendable {
    var login: String
    var competitors: [String]
    var window: String
    var timeZone: String
}

/// Keeps the relay's registration in step with Live rank. `LiveRankController` calls `sync`
/// after every pass with what should be registered (nil = nothing: Live rank off, or
/// disconnected) and the activity it kept; this sends only what changed.
@MainActor
final class LiveRankRelay {
    private let client: any LiveRankRelayClient
    private let store: any LiveRankRelayStore
    private let environment: String
    private let now: @Sendable () -> Date
    private var sent: RelaySentState
    private var pushToStartToken: String?
    /// Every activity's latest push token, by activity ID. ActivityKit reports a token once, so
    /// it's kept to re-report after the registration is deleted and made again.
    private var activityTokens: [String: String] = [:]
    /// After a 429, nothing is sent before this.
    private var notBefore: Date?

    init(_ dependencies: LiveRankRelayDependencies, now: @escaping @Sendable () -> Date) {
        client = dependencies.client
        store = dependencies.store
        environment = dependencies.environment
        self.now = now
        sent = dependencies.store.loadSent()
    }

    /// The registration the relay holds for this iPhone, if any.
    var registered: RelayRegistration? { sent.registration }

    func record(_ token: LiveRankPushToken) {
        switch token {
        case .pushToStart(let data): pushToStartToken = data.hexString
        case .activity(let id, let data): activityTokens[id] = data.hexString
        }
    }

    func sync(board: RelayBoard?, activityID: String?) async {
        if let notBefore, now() < notBefore { return }
        guard let board else {
            await unregisterIfNeeded()
            return
        }
        let installation = installationOrNew()
        let registration = RelayRegistration(
            login: board.login, competitors: board.competitors, window: board.window,
            timeZone: board.timeZone, environment: environment, pushToStartToken: pushToStartToken
        )
        if sent.registration != registration {
            do {
                try await client.register(registration, as: installation)
            } catch {
                handle(error)
                return
            }
            sent.registration = registration
            store.saveSent(sent)
        }
        if let activityID { await report(activityID: activityID, as: installation) }
    }

    /// Report an activity's token when the relay already holds a registration it belongs to,
    /// without touching the registration. For token updates that arrive while the app can't
    /// read its board (a background launch before first unlock).
    func reportIfRegistered(activityID: String) async {
        guard sent.registration != nil, let installation = store.loadInstallation() else { return }
        if let notBefore, now() < notBefore { return }
        await report(activityID: activityID, as: installation)
    }

    private func report(activityID: String, as installation: RelayInstallation) async {
        guard let token = activityTokens[activityID] else { return }
        let activity = RelaySentState.Activity(id: activityID, pushToken: token)
        guard sent.activity != activity else { return }
        do {
            try await client.reportActivity(id: activityID, pushToken: token, as: installation)
        } catch {
            handle(error)
            return
        }
        sent.activity = activity
        store.saveSent(sent)
    }

    private func unregisterIfNeeded() async {
        guard sent.registration != nil || sent.activity != nil else { return }
        if let installation = store.loadInstallation() {
            do {
                try await client.unregister(installation)
            } catch RelayClientError.rejected(status: 401, _) {
                // Not ours to delete (the relay knows another secret): nothing left to revoke.
            } catch {
                handle(error)
                return
            }
        }
        sent = RelaySentState()
        store.saveSent(sent)
    }

    private func installationOrNew() -> RelayInstallation {
        if let installation = store.loadInstallation() { return installation }
        let installation = RelayInstallation.random()
        store.saveInstallation(installation)
        return installation
    }

    private func handle(_ error: any Error) {
        switch error as? RelayClientError {
        case .rejected(status: 401, _):
            // The relay holds a different secret for this ID: start over with a new identity.
            store.saveInstallation(nil)
            sent = RelaySentState()
            store.saveSent(sent)
        case .rejected(status: 404, _):
            // The relay forgot this installation: register again on the next pass.
            sent = RelaySentState()
            store.saveSent(sent)
        case .rejected(status: 429, let retryAfter):
            notBefore = now().addingTimeInterval(retryAfter ?? 60)
        default:
            // Offline, 409, or a server error: the next pass tries again.
            break
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

// MARK: - Storage

/// The install identity in the Keychain (readable after first unlock, so a background launch
/// can report a token; never backed up to another device), and what was sent in the App Group.
final class DeviceLiveRankRelayStore: LiveRankRelayStore, @unchecked Sendable {
    static let sentKey = "liveRank.relaySent"
    private let service: String
    private let account = "relay-installation"
    private let defaults: UserDefaults

    init(
        service: String = "com.addisonk.CommitStandings.relay",
        defaults: UserDefaults = UserDefaults(suiteName: UserDefaultsLiveRankPersistence.appGroup) ?? .standard
    ) {
        self.service = service
        self.defaults = defaults
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func loadInstallation() -> RelayInstallation? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(RelayInstallation.self, from: data)
    }

    func saveInstallation(_ installation: RelayInstallation?) {
        SecItemDelete(baseQuery as CFDictionary)
        guard let installation, let data = try? JSONEncoder().encode(installation) else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func loadSent() -> RelaySentState {
        defaults.data(forKey: Self.sentKey)
            .flatMap { try? JSONDecoder().decode(RelaySentState.self, from: $0) } ?? RelaySentState()
    }

    func saveSent(_ sent: RelaySentState) {
        defaults.set(try? JSONEncoder().encode(sent), forKey: Self.sentKey)
    }
}

final class InMemoryLiveRankRelayStore: LiveRankRelayStore, @unchecked Sendable {
    private let lock = NSLock()
    private var installation: RelayInstallation?
    private var sent = RelaySentState()

    init(installation: RelayInstallation? = nil, sent: RelaySentState = RelaySentState()) {
        self.installation = installation
        self.sent = sent
    }

    func loadInstallation() -> RelayInstallation? { lock.withLock { installation } }
    func saveInstallation(_ installation: RelayInstallation?) { lock.withLock { self.installation = installation } }
    func loadSent() -> RelaySentState { lock.withLock { sent } }
    func saveSent(_ sent: RelaySentState) { lock.withLock { self.sent = sent } }
}

// MARK: - Configuration and HTTP

/// The relay this build talks to, from the `COMMITTED_RELAY_URL` and
/// `COMMITTED_APNS_ENVIRONMENT` build settings (surfaced as Info.plist keys). An empty URL
/// means no relay: Live rank stays on-device only.
struct RelayConfiguration: Equatable {
    static let urlKey = "CommittedRelayURL"
    static let environmentKey = "CommittedAPNsEnvironment"

    var baseURL: URL
    var environment: String

    init?(info: [String: Any]?) {
        guard let raw = (info?[Self.urlKey] as? String)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
              let url = URL(string: raw), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host() != nil
        else { return nil }
        baseURL = url
        let environment = info?[Self.environmentKey] as? String
        self.environment = environment == "production" ? "production" : "sandbox"
    }
}

/// JSON over HTTPS with the install secret as a bearer token. Requests time out after 10
/// seconds so a missing relay never holds up a refresh (or a background task) for long.
struct HTTPLiveRankRelayClient: LiveRankRelayClient {
    let baseURL: URL
    var session: URLSession = .shared
    var timeout: TimeInterval = 10

    func register(_ registration: RelayRegistration, as installation: RelayInstallation) async throws {
        try await send("PUT", path: installation.id, body: JSONEncoder().encode(registration), as: installation)
    }

    func reportActivity(id: String, pushToken: String, as installation: RelayInstallation) async throws {
        let body = try JSONEncoder().encode(["activityId": id, "pushToken": pushToken])
        try await send("PUT", path: "\(installation.id)/activity", body: body, as: installation)
    }

    func unregister(_ installation: RelayInstallation) async throws {
        try await send("DELETE", path: installation.id, body: nil, as: installation)
    }

    private func send(_ method: String, path: String, body: Data?, as installation: RelayInstallation) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1/installations/\(path)"), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(installation.secret)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw RelayClientError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw RelayClientError.unreachable("not HTTP") }
        guard (200..<300).contains(http.statusCode) else {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw RelayClientError.rejected(status: http.statusCode, retryAfter: retryAfter)
        }
    }
}
