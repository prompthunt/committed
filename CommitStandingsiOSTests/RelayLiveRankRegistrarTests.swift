import Foundation
import Testing
@testable import CommitStandingsiOS

/// The Committed relay's device API, in memory: records every call in order.
final class FakeRelayAPI: LiveRankRelayAPI, @unchecked Sendable {
    enum Call: Equatable {
        case register(RelayRegistration)
        case activity(RelayActivityReport)
        case unregister
    }

    private(set) var calls: [Call] = []
    private(set) var installations: [RelayInstallation.Credentials] = []
    /// Fail every call while set, like an offline phone.
    var failure: (any Error)?
    /// What `reportActivity` answers when the relay has no registration (404 `not_registered`).
    var activityFailure: (any Error)?
    /// Windows this relay doesn't know, like one from before This month: it answers 400
    /// `invalid_window` for them.
    var rejectedWindows: Set<String> = []
    /// Every registration sent, accepted or not.
    private(set) var registerAttempts = 0

    func register(_ registration: RelayRegistration, as installation: RelayInstallation.Credentials) async throws {
        installations.append(installation)
        registerAttempts += 1
        if let failure { throw failure }
        if rejectedWindows.contains(registration.window) { throw LiveRankRelayError.invalidWindow }
        calls.append(.register(registration))
    }

    func reportActivity(_ report: RelayActivityReport, as installation: RelayInstallation.Credentials) async throws {
        installations.append(installation)
        if let failure { throw failure }
        if let activityFailure { throw activityFailure }
        calls.append(.activity(report))
    }

    func unregister(_ installation: RelayInstallation.Credentials) async throws {
        installations.append(installation)
        if let failure { throw failure }
        calls.append(.unregister)
    }

    var registrations: [RelayRegistration] {
        calls.compactMap { if case .register(let registration) = $0 { registration } else { nil } }
    }
}

/// The relay client behind `LiveRankRegistrar`: what it sends, when, and what it holds back.
@MainActor
struct RelayLiveRankRegistrarTests {
    let api = FakeRelayAPI()
    let installationStore = InMemoryRelayInstallationStore()
    let notifications = NotificationCenter()
    let zone = TimeZoneBox("America/New_York")

    private func makeRegistrar(environment: RelayAPNsEnvironment = .sandbox) -> RelayLiveRankRegistrar {
        let zone = zone
        return RelayLiveRankRegistrar(
            api: api,
            installations: installationStore,
            apnsEnvironment: environment,
            timeZone: { zone.value },
            notificationCenter: notifications
        )
    }

    private let board = LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada", "bo"], window: .daily)

    @Test func activitiesTakePushUpdates() {
        #expect(makeRegistrar().pushUpdates == .token)
    }

    @Test func registersTheBoardWithTimeZoneAndEnvironment() async {
        let registrar = makeRegistrar(environment: .production)

        await registrar.liveRankDidChange(board)

        #expect(api.calls == [.register(RelayRegistration(
            pushToStartToken: nil, login: "me", competitors: ["me", "ada", "bo"], window: "daily",
            timeZone: "America/New_York", apnsEnvironment: "production"
        ))])
    }

    @Test func createsOneInstallationAndKeepsIt() async throws {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)
        await registrar.liveRankDidChange(LiveRankConfiguration(selfLogin: "me", competitors: ["me"], window: .daily))

        let saved = try #require(installationStore.load())
        #expect(api.installations.allSatisfy { $0 == saved.credentials })
        #expect(saved.id.count >= 8 && saved.id.count <= 64)
        #expect(saved.id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        #expect(saved.secret.count >= 32 && saved.secret.count <= 256)
        #expect(saved.isRegistered)

        // A relaunch reuses the same installation.
        let relaunched = makeRegistrar()
        await relaunched.liveRankDidChange(board)
        #expect(api.installations.last == saved.credentials)
    }

    // MARK: Re-registration triggers

    @Test func visibilityWindowAndRosterChangesReRegister() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)
        // Hiding bo, a people sync adding cy, and a Window change each come through as a new configuration.
        await registrar.liveRankDidChange(LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada"], window: .daily))
        await registrar.liveRankDidChange(LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada", "cy"], window: .daily))
        await registrar.liveRankDidChange(LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada", "cy"], window: .weekly))

        #expect(api.registrations.map(\.competitors) == [
            ["me", "ada", "bo"], ["me", "ada"], ["me", "ada", "cy"], ["me", "ada", "cy"],
        ])
        #expect(api.registrations.map(\.window) == ["daily", "daily", "daily", "weekly"])
    }

    @Test func sendsNothingWhenNothingChanged() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)
        await registrar.liveRankDidChange(board)
        await registrar.retryPendingWork()

        #expect(api.calls.count == 1)
    }

    @Test func timeZoneChangeReRegisters() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)

        zone.value = TimeZone(identifier: "Asia/Tokyo")!
        notifications.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await registrar.idle()

        #expect(api.registrations.map(\.timeZone) == ["America/New_York", "Asia/Tokyo"])
    }

    @Test func pushToStartTokenChangeReRegisters() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)

        await registrar.pushToStartTokenDidChange(Data([0xAB, 0x01, 0xFF]))
        await registrar.pushToStartTokenDidChange(Data([0xAB, 0x01, 0xFF]))
        await registrar.pushToStartTokenDidChange(Data([0x02]))

        #expect(api.registrations.map(\.pushToStartToken) == [nil, "ab01ff", "02"])
    }

    @Test func aTokenBeforeTheBoardLoadsGoesInTheFirstRegistration() async {
        let registrar = makeRegistrar()
        await registrar.pushToStartTokenDidChange(Data([0x0A]))
        #expect(api.calls.isEmpty)

        await registrar.liveRankDidChange(board)

        #expect(api.registrations.map(\.pushToStartToken) == ["0a"])
    }

    // MARK: Activities

    @Test func reportsEachActivityTokenOnce() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)

        await registrar.activityPushTokenDidChange(activityID: "A", token: Data([0x01]))
        await registrar.activityPushTokenDidChange(activityID: "A", token: Data([0x01]))
        await registrar.activityPushTokenDidChange(activityID: "B", token: Data([0xFE]))
        // iOS can rotate an activity's token: that's a new report.
        await registrar.activityPushTokenDidChange(activityID: "A", token: Data([0x03]))

        #expect(Array(api.calls.dropFirst()) == [
            .activity(RelayActivityReport(activityId: "A", pushToken: "01")),
            .activity(RelayActivityReport(activityId: "B", pushToken: "fe")),
            .activity(RelayActivityReport(activityId: "A", pushToken: "03")),
        ])
    }

    @Test func anActivityTokenBeforeRegistrationWaitsForIt() async {
        // A relay-started activity can report its token before the board has loaded on a cold launch.
        let registrar = makeRegistrar()
        await registrar.activityPushTokenDidChange(activityID: "A", token: Data([0x01]))
        #expect(api.calls.isEmpty)

        await registrar.liveRankDidChange(board)

        #expect(api.calls == [
            .register(api.registrations[0]),
            .activity(RelayActivityReport(activityId: "A", pushToken: "01")),
        ])
    }

    @Test func aRelayStartedActivityIsReportedOnABackgroundLaunch() async {
        // Push-to-start wakes the app in the background: no board sync runs, but the relay already
        // holds this installation's registration from an earlier launch.
        let installation = RelayInstallation(id: "install-1234", secret: String(repeating: "a", count: 64), isRegistered: true)
        installationStore.save(installation)
        let registrar = makeRegistrar()

        await registrar.activityPushTokenDidChange(activityID: "R", token: Data([0x7F]))

        #expect(api.calls == [.activity(RelayActivityReport(activityId: "R", pushToken: "7f"))])
        #expect(api.installations == [installation.credentials])
    }

    @Test func aBackgroundReportToAMissingRegistrationStopsTrying() async {
        installationStore.save(RelayInstallation(id: "install-1234", secret: String(repeating: "a", count: 64), isRegistered: true))
        api.activityFailure = LiveRankRelayError.status(404)
        let registrar = makeRegistrar()

        await registrar.activityPushTokenDidChange(activityID: "R", token: Data([0x7F]))
        api.activityFailure = nil
        await registrar.retryPendingWork()

        // Held until the board is known, then registered and reported.
        #expect(api.calls.isEmpty)
        #expect(installationStore.load()?.isRegistered == false)
        await registrar.liveRankDidChange(board)
        #expect(api.calls.count == 2)
        #expect(api.calls.last == .activity(RelayActivityReport(activityId: "R", pushToken: "7f")))
    }

    @Test func aLostRegistrationIsRestoredBeforeReportingTheActivity() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)
        api.activityFailure = LiveRankRelayError.status(404)

        await registrar.activityPushTokenDidChange(activityID: "A", token: Data([0x01]))
        api.activityFailure = nil
        await registrar.retryPendingWork()

        #expect(api.calls.count == 3)
        #expect(api.registrations.count == 2)
        #expect(api.calls.last == .activity(RelayActivityReport(activityId: "A", pushToken: "01")))
    }

    // MARK: Unregistering

    @Test func offOrDisconnectUnregisters() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)

        await registrar.liveRankDidChange(nil)

        #expect(api.calls.last == .unregister)
        #expect(installationStore.load()?.isRegistered == false)

        // Turning back on registers again, even with the same board.
        await registrar.liveRankDidChange(board)
        #expect(api.registrations.count == 2)
    }

    @Test func unregistersAfterARelaunch() async {
        await makeRegistrar().liveRankDidChange(board)

        // Disconnect on a later launch: this process never registered, but the installation did.
        await makeRegistrar().liveRankDidChange(nil)

        #expect(api.calls.last == .unregister)
    }

    @Test func neverRegisteredMeansNothingToDelete() async {
        await makeRegistrar().liveRankDidChange(nil)
        #expect(api.calls.isEmpty)
    }

    @Test func activityTokensWhileOffAreDropped() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(nil)
        await registrar.activityPushTokenDidChange(activityID: "A", token: Data([0x01]))
        #expect(api.calls.isEmpty)
    }

    // MARK: Failures

    @Test func aFailedRegistrationIsRetriedLater() async {
        let registrar = makeRegistrar()
        api.failure = URLError(.notConnectedToInternet)
        await registrar.liveRankDidChange(board)
        #expect(api.calls.isEmpty)

        api.failure = nil
        await registrar.retryPendingWork()

        #expect(api.registrations.count == 1)
    }

    // MARK: A relay older than This month

    private let monthBoard = LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada", "bo"], window: .month)

    /// A relay from before This month answers 400 `invalid_window`. The app stops asking, takes back
    /// the registration it had (so the relay stops pushing another Window's rank, or starting one,
    /// on this phone), and holds back push tokens: the app keeps Live rank up to date itself.
    @Test func aRelayThatDoesNotKnowTheWindowIsLeftAlone() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)
        api.rejectedWindows = ["month"]
        #expect(registrar.serves(.month))

        await registrar.liveRankDidChange(monthBoard)

        #expect(!registrar.serves(.month))
        #expect(registrar.serves(.daily))
        #expect(api.calls.last == .unregister)
        #expect(installationStore.load()?.isRegistered == false)

        let attempts = api.registerAttempts
        await registrar.retryPendingWork()
        await registrar.pushToStartTokenDidChange(Data([0xAB]))
        await registrar.activityPushTokenDidChange(activityID: "M", token: Data([0x02]))
        await registrar.retryPendingWork()

        #expect(api.registerAttempts == attempts)
        #expect(api.calls.last == .unregister)
    }

    /// Back on a Window the relay knows, it takes over again, and This month is asked about afresh.
    @Test func aWindowTheRelayKnowsRegistersAgain() async {
        let registrar = makeRegistrar()
        api.rejectedWindows = ["month"]
        await registrar.liveRankDidChange(monthBoard)
        #expect(!registrar.serves(.month))

        await registrar.liveRankDidChange(board)

        #expect(registrar.serves(.month))
        #expect(api.registrations.last?.window == "daily")
        #expect(installationStore.load()?.isRegistered == true)
    }

    /// Once the relay is updated, the next launch's registration for This month goes through.
    @Test func theNextLaunchAsksAgain() async {
        api.rejectedWindows = ["month"]
        await makeRegistrar().liveRankDidChange(monthBoard)

        api.rejectedWindows = []
        let relaunched = makeRegistrar()
        await relaunched.liveRankDidChange(monthBoard)

        #expect(api.registrations.last?.window == "month")
        #expect(relaunched.serves(.month))
    }

    /// Any other rejection isn't about the Window: it's retried later, as before.
    @Test func anotherBadRequestIsRetried() async {
        let registrar = makeRegistrar()
        api.failure = LiveRankRelayError.status(400)
        await registrar.liveRankDidChange(monthBoard)
        #expect(registrar.serves(.month))

        api.failure = nil
        await registrar.retryPendingWork()

        #expect(api.registrations.map(\.window) == ["month"])
    }

    @Test func aFailedUnregistrationIsRetriedLater() async {
        let registrar = makeRegistrar()
        await registrar.liveRankDidChange(board)
        api.failure = URLError(.timedOut)
        await registrar.liveRankDidChange(nil)

        api.failure = nil
        await registrar.retryPendingWork()

        #expect(api.calls.last == .unregister)
        #expect(installationStore.load()?.isRegistered == false)
    }
}

/// A mutable time zone the test changes, read by the registrar.
final class TimeZoneBox: @unchecked Sendable {
    var value: TimeZone
    init(_ identifier: String) { value = TimeZone(identifier: identifier)! }
}

/// Registration body and requests: exactly the keys the relay accepts (unknown keys are a 400).
struct LiveRankRelayRequestTests {
    let base = URL(string: "http://localhost:8787")!
    let credentials = RelayInstallation.Credentials(id: "6F1C-test-install", secret: String(repeating: "s", count: 64))

    @Test func registrationIsAPutWithExactlyTheRelaysKeys() throws {
        let request = try URLSessionLiveRankRelayAPI.request(
            .register(RelayRegistration(pushToStartToken: nil, login: "me", competitors: ["me", "ada"], window: "weekly",
                                        timeZone: "Europe/Paris", apnsEnvironment: "sandbox")),
            baseURL: base, installation: credentials
        )

        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "http://localhost:8787/v1/installations/6F1C-test-install")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + String(repeating: "s", count: 64))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(body.keys) == ["pushToStartToken", "login", "competitors", "window", "timeZone", "apnsEnvironment"])
        #expect(body["pushToStartToken"] is NSNull)
        #expect(body["competitors"] as? [String] == ["me", "ada"])
        #expect(body["window"] as? String == "weekly")
    }

    @Test func activityReportIsAPutToTheActivityPath() throws {
        let request = try URLSessionLiveRankRelayAPI.request(
            .activity(RelayActivityReport(activityId: "A-1", pushToken: "ab")), baseURL: base, installation: credentials
        )

        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/installations/6F1C-test-install/activity")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(body.keys) == ["activityId", "pushToken"])
    }

    @Test func unregisterIsADelete() throws {
        let request = try URLSessionLiveRankRelayAPI.request(.unregister, baseURL: base, installation: credentials)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/installations/6F1C-test-install")
        #expect(request.httpBody == nil)
    }

    /// The relay's error body says when the Window is what it rejected: `invalid_window` from a relay
    /// older than This month. Other failures keep their status.
    @Test func readsInvalidWindowFromTheRelaysAnswer() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RejectingRelay.self]
        let api = URLSessionLiveRankRelayAPI(baseURL: base, session: URLSession(configuration: config))
        func registration(_ window: String) -> RelayRegistration {
            RelayRegistration(pushToStartToken: nil, login: "me", competitors: ["me"], window: window,
                              timeZone: "UTC", apnsEnvironment: "sandbox")
        }

        await #expect(throws: LiveRankRelayError.invalidWindow) {
            try await api.register(registration("month"), as: self.credentials)
        }
        await #expect(throws: LiveRankRelayError.status(400)) {
            try await api.register(registration("weekly"), as: self.credentials)
        }
        await #expect(throws: LiveRankRelayError.status(429)) {
            try await api.register(registration("daily"), as: self.credentials)
        }
    }

    @Test func aBaseURLWithAPathKeepsIt() throws {
        let request = try URLSessionLiveRankRelayAPI.request(
            .unregister, baseURL: URL(string: "https://relay.example.com/staging/")!, installation: credentials
        )
        #expect(request.url?.absoluteString == "https://relay.example.com/staging/v1/installations/6F1C-test-install")
    }
}

/// Where the relay URL comes from: the `COMMITTED_RELAY_URL` build setting, through Info.plist.
struct LiveRankRelaySettingsTests {
    @Test func noURLMeansNoRelay() {
        #expect(LiveRankRelaySettings(info: [:]).baseURL == nil)
        #expect(LiveRankRelaySettings(info: ["CommittedRelayURL": ""]).baseURL == nil)
        #expect(LiveRankRelaySettings(info: ["CommittedRelayURL": "  "]).baseURL == nil)
    }

    @Test func readsTheURLAndEnvironment() {
        let settings = LiveRankRelaySettings(info: [
            "CommittedRelayURL": "http://localhost:8787", "CommittedAPNsEnvironment": "production",
        ])
        #expect(settings.baseURL == URL(string: "http://localhost:8787"))
        #expect(settings.apnsEnvironment == .production)
    }

    @Test func environmentDefaultsToSandbox() {
        #expect(LiveRankRelaySettings(info: ["CommittedRelayURL": "http://localhost:8787"]).apnsEnvironment == .sandbox)
        #expect(LiveRankRelaySettings(info: ["CommittedAPNsEnvironment": "development"]).apnsEnvironment == .sandbox)
    }

    @Test func onlyHTTPURLsCount() {
        #expect(LiveRankRelaySettings(info: ["CommittedRelayURL": "localhost:8787"]).baseURL == nil)
    }
}

/// A relay that rejects registrations by Window: "month" as one from before This month does
/// (400 `invalid_window`), "weekly" with another 400, anything else rate limited (429).
private final class RejectingRelay: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let window = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["window"] as? String
        let (status, error) = switch window {
        case "month": (400, "invalid_window")
        case "weekly": (400, "invalid_time_zone")
        default: (429, "rate_limited")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":"\#(error)"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
