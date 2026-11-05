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

    func register(_ registration: RelayRegistration, as installation: RelayInstallation.Credentials) async throws {
        installations.append(installation)
        if let failure { throw failure }
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
