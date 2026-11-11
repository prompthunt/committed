import Foundation
import os

enum LiveRankLog {
    /// `log stream --predicate 'subsystem == "com.addisonk.CommitStandings.iOS"'` shows what the app
    /// sends the relay. Tokens are logged as short prefixes; the install secret never.
    static let relay = Logger(subsystem: "com.addisonk.CommitStandings.iOS", category: "LiveRankRelay")
}

/// This iPhone's identity at the Committed relay: a random installation ID and a random secret,
/// generated once and kept in the Keychain. The relay stores only the secret's hash; the first
/// registration claims the ID.
struct RelayInstallation: Codable, Equatable, Sendable {
    struct Credentials: Equatable, Sendable {
        let id: String
        let secret: String
    }

    var id: String
    var secret: String
    /// Whether the relay may still hold a registration for this installation, so turning Live rank
    /// off or disconnecting after a relaunch still deletes it.
    var isRegistered: Bool

    var credentials: Credentials { Credentials(id: id, secret: secret) }

    static func generate() -> RelayInstallation {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return RelayInstallation(id: UUID().uuidString, secret: Data(bytes).lowercaseHex, isRegistered: false)
    }
}

protocol RelayInstallationStoring: AnyObject {
    func load() -> RelayInstallation?
    func save(_ installation: RelayInstallation)
}

final class InMemoryRelayInstallationStore: RelayInstallationStoring {
    private var installation: RelayInstallation?
    init(_ installation: RelayInstallation? = nil) { self.installation = installation }
    func load() -> RelayInstallation? { installation }
    func save(_ installation: RelayInstallation) { self.installation = installation }
}

/// Which APNs the relay pushes through, matching the app's `aps-environment` entitlement:
/// `development` builds get `sandbox`, App Store and TestFlight builds get `production`.
enum RelayAPNsEnvironment: String, Sendable {
    case sandbox
    case production
}

/// The body of `PUT /v1/installations/{id}`: exactly the keys the relay accepts.
struct RelayRegistration: Equatable, Sendable, Encodable {
    var pushToStartToken: String?
    var login: String
    var competitors: [String]
    var window: String
    var timeZone: String
    var apnsEnvironment: String

    private enum CodingKeys: String, CodingKey {
        case pushToStartToken, login, competitors, window, timeZone, apnsEnvironment
    }

    // The relay expects `pushToStartToken: null` until iOS issues one, not a missing key.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pushToStartToken, forKey: .pushToStartToken)
        try container.encode(login, forKey: .login)
        try container.encode(competitors, forKey: .competitors)
        try container.encode(window, forKey: .window)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(apnsEnvironment, forKey: .apnsEnvironment)
    }
}

/// The body of `PUT /v1/installations/{id}/activity`.
struct RelayActivityReport: Equatable, Sendable, Encodable {
    var activityId: String
    var pushToken: String
}

enum LiveRankRelayError: Error, Equatable {
    /// The relay answered with this HTTP status.
    case status(Int)
    /// 400 `invalid_window`: the relay doesn't rank the registration's Window, as a relay from
    /// before This month doesn't rank `"month"`.
    case invalidWindow

    /// The error for a relay's non-2xx answer, from its status and its `{"error": "<code>"}` body.
    init(status: Int, body: Data) {
        struct Answer: Decodable { let error: String }
        if status == 400, (try? JSONDecoder().decode(Answer.self, from: body))?.error == "invalid_window" {
            self = .invalidWindow
        } else {
            self = .status(status)
        }
    }
}

/// The relay's device API (see `relay/README.md`). Every call authenticates with the
/// installation's secret.
protocol LiveRankRelayAPI: Sendable {
    func register(_ registration: RelayRegistration, as installation: RelayInstallation.Credentials) async throws
    func reportActivity(_ report: RelayActivityReport, as installation: RelayInstallation.Credentials) async throws
    func unregister(_ installation: RelayInstallation.Credentials) async throws
}

/// Hands push tokens from ActivityKit to the relay client.
@MainActor
protocol LiveRankTokenReceiving: AnyObject {
    func pushToStartTokenDidChange(_ token: Data) async
    func activityPushTokenDidChange(activityID: String, token: Data) async
}

/// Phase 2: the Committed relay keeps Live rank current while the app is closed.
///
/// `LiveRankController` tells it the board (`LiveRankConfiguration`) whenever it changes, and nil
/// when Live rank turns off or GitHub disconnects. ActivityKit's token streams arrive through
/// `LiveRankTokenReceiving`. Everything funnels into one `flush()` that brings the relay in line:
/// register when the registration body changed (board, push-to-start token, time zone), report
/// each activity's push token once it's registered, and delete the registration when there's no
/// board. A failed call leaves the work pending; the next trigger or `retryPendingWork()` tries
/// again. Nothing is sent when nothing changed, which keeps well inside the relay's 30 writes per
/// 10 minutes.
///
/// A relay older than the app can reject the Window (`invalid_window`, This month on a relay from
/// before it). Then the registrar stops asking, deletes the registration it had, so the relay
/// stops pushing (or push-to-starting) another Window's rank on this phone, and holds back push
/// tokens: the app keeps Live rank current itself (`serves`). Another Window, or the next launch,
/// asks again, which is how an updated relay is found.
@MainActor
final class RelayLiveRankRegistrar: LiveRankRegistrar, LiveRankTokenReceiving {
    private let api: any LiveRankRelayAPI
    private let installations: any RelayInstallationStoring
    private let apnsEnvironment: RelayAPNsEnvironment
    private let timeZone: @Sendable () -> TimeZone
    private let backgroundTime: (any BackgroundTimeProviding)?

    /// The board to register; nil until the controller first reports (a cold launch).
    private var configuration: LiveRankConfiguration?
    /// Live rank is off or GitHub disconnected: delete the registration.
    private var isTurnedOff = false
    private var pushToStartToken: String?
    /// The last registration the relay accepted in this process.
    private var lastRegistered: RelayRegistration?
    /// The Window the relay rejected with `invalid_window` in this process, until Live rank moves
    /// to another Window.
    private var rejectedWindow: ContributionWindow?
    /// Activity push tokens waiting for a registration (activity ID → token), in arrival order.
    private var pendingActivities: [(id: String, token: String)] = []
    private var reportedActivities: [String: String] = [:]
    private var isFlushing = false
    private var flushAgain = false
    private var pending: Task<Void, Never>?
    private var timeZoneObserver: (any NSObjectProtocol)?

    init(
        api: any LiveRankRelayAPI,
        installations: any RelayInstallationStoring,
        apnsEnvironment: RelayAPNsEnvironment,
        timeZone: @escaping @Sendable () -> TimeZone = { TimeZone.current },
        notificationCenter: NotificationCenter = .default,
        backgroundTime: (any BackgroundTimeProviding)? = nil
    ) {
        self.api = api
        self.installations = installations
        self.apnsEnvironment = apnsEnvironment
        self.timeZone = timeZone
        self.backgroundTime = backgroundTime
        // The relay computes "Today" on your local calendar, so a new time zone re-registers.
        timeZoneObserver = notificationCenter.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.timeZoneDidChange() }
            } else {
                Task { @MainActor in self?.timeZoneDidChange() }
            }
        }
    }

    var pushUpdates: LiveRankPushUpdates { .token }

    func serves(_ window: ContributionWindow) -> Bool { window != rejectedWindow }

    func liveRankDidChange(_ configuration: LiveRankConfiguration?) async {
        self.configuration = configuration
        isTurnedOff = configuration == nil
        if isTurnedOff { pendingActivities.removeAll() }
        if let window = configuration?.window, window != rejectedWindow { rejectedWindow = nil }
        await flush()
    }

    func retryPendingWork() async {
        await flush()
    }

    // MARK: - Tokens

    func pushToStartTokenDidChange(_ token: Data) async {
        pushToStartToken = token.lowercaseHex
        await flush()
    }

    func activityPushTokenDidChange(activityID: String, token: Data) async {
        // Live rank is off: the relay has no registration to attach it to. Before the controller
        // has reported at all (a cold launch), hold the token until the board is known.
        guard !isTurnedOff, configuration.map({ serves($0.window) }) ?? true else { return }
        let hex = token.lowercaseHex
        guard reportedActivities[activityID] != hex else { return }
        pendingActivities.removeAll { $0.id == activityID }
        pendingActivities.append((activityID, hex))
        await flush()
    }

    private func timeZoneDidChange() {
        pending = Task { await flush() }
    }

    /// Wait for work started by a time-zone change.
    func idle() async {
        await pending?.value
    }

    // MARK: - Flush

    private func flush() async {
        if isFlushing {
            flushAgain = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }
        let token = backgroundTime?.begin("Committed relay")
        defer { if let token { backgroundTime?.end(token) } }
        repeat {
            flushAgain = false
            await flushOnce()
        } while flushAgain
    }

    private func flushOnce() async {
        if isTurnedOff {
            await unregisterIfNeeded()
            return
        }
        if let configuration {
            // The relay can't rank this Window: nothing to register or report until it changes.
            guard serves(configuration.window) else { return }
            guard await register(configuration) else { return }
        } else {
            // No board yet: a background launch, for example when the relay started an activity by
            // push-to-start. If the relay holds this installation from an earlier launch, report
            // the activity now (the relay counts its age from the report); otherwise wait.
            guard installations.load()?.isRegistered == true else { return }
        }
        guard var installation = installations.load() else { return }

        while let next = pendingActivities.first {
            do {
                try await api.reportActivity(
                    RelayActivityReport(activityId: next.id, pushToken: next.token), as: installation.credentials
                )
            } catch LiveRankRelayError.status(404) {
                // The relay lost the registration (deleted elsewhere, or a fresh database):
                // register again once the board is known, then report.
                lastRegistered = nil
                installation.isRegistered = false
                installations.save(installation)
                return
            } catch {
                LiveRankLog.relay.error("activity report failed: \(String(describing: error), privacy: .public)")
                return
            }
            LiveRankLog.relay.info("reported activity \(next.id, privacy: .public)")
            pendingActivities.removeFirst()
            reportedActivities[next.id] = next.token
        }
    }

    /// PUT the registration when its body changed. False when the relay couldn't be reached.
    private func register(_ configuration: LiveRankConfiguration) async -> Bool {
        var installation = installations.load() ?? {
            let new = RelayInstallation.generate()
            installations.save(new)
            return new
        }()
        let registration = RelayRegistration(
            pushToStartToken: pushToStartToken,
            login: configuration.selfLogin,
            competitors: configuration.competitors,
            window: configuration.window.rawValue,
            timeZone: timeZone().identifier,
            apnsEnvironment: apnsEnvironment.rawValue
        )
        guard registration != lastRegistered || !installation.isRegistered else { return true }
        do {
            try await api.register(registration, as: installation.credentials)
        } catch LiveRankRelayError.invalidWindow {
            LiveRankLog.relay.info("relay doesn't rank \(registration.window, privacy: .public): Live rank updates from the app")
            rejectedWindow = configuration.window
            pendingActivities.removeAll()
            await unregisterIfNeeded()
            return false
        } catch {
            LiveRankLog.relay.error("register failed: \(String(describing: error), privacy: .public)")
            return false
        }
        LiveRankLog.relay.info("registered \(registration.competitors.count) people, \(registration.window, privacy: .public), push-to-start \(registration.pushToStartToken == nil ? "none" : "yes", privacy: .public)")
        lastRegistered = registration
        if !installation.isRegistered {
            installation.isRegistered = true
            installations.save(installation)
        }
        return true
    }

    private func unregisterIfNeeded() async {
        guard var installation = installations.load(), installation.isRegistered else { return }
        do {
            try await api.unregister(installation.credentials)
        } catch {
            LiveRankLog.relay.error("unregister failed: \(String(describing: error), privacy: .public)")
            return
        }
        LiveRankLog.relay.info("unregistered")
        installation.isRegistered = false
        installations.save(installation)
        lastRegistered = nil
        reportedActivities.removeAll()
    }
}

extension Data {
    /// APNs tokens as the relay expects them: lowercase hex.
    var lowercaseHex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
