import Foundation

/// Where the Committed relay lives, from the app's Info.plist. The values come from build settings:
/// `COMMITTED_RELAY_URL` (empty by default, so Live rank stays phase 1) and
/// `COMMITTED_APNS_ENVIRONMENT` (`sandbox` for Debug, `production` for Release). For a local relay,
/// build with `COMMITTED_RELAY_URL=http://localhost:8787` (see `relay/README.md`).
struct LiveRankRelaySettings: Equatable {
    let baseURL: URL?
    let apnsEnvironment: RelayAPNsEnvironment

    init(info: [String: Any]) {
        let raw = (info["CommittedRelayURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
           url.host != nil {
            baseURL = url
        } else {
            baseURL = nil
        }
        apnsEnvironment = (info["CommittedAPNsEnvironment"] as? String).flatMap(RelayAPNsEnvironment.init) ?? .sandbox
    }

    static var main: LiveRankRelaySettings {
        LiveRankRelaySettings(info: Bundle.main.infoDictionary ?? [:])
    }
}

/// The relay's device API over HTTPS (or HTTP for a local `wrangler dev`).
struct URLSessionLiveRankRelayAPI: LiveRankRelayAPI {
    enum Call {
        case register(RelayRegistration)
        case activity(RelayActivityReport)
        case unregister
    }

    let baseURL: URL
    var session: URLSession = .shared

    func register(_ registration: RelayRegistration, as installation: RelayInstallation.Credentials) async throws {
        try await send(.register(registration), as: installation)
    }

    func reportActivity(_ report: RelayActivityReport, as installation: RelayInstallation.Credentials) async throws {
        try await send(.activity(report), as: installation)
    }

    func unregister(_ installation: RelayInstallation.Credentials) async throws {
        try await send(.unregister, as: installation)
    }

    private func send(_ call: Call, as installation: RelayInstallation.Credentials) async throws {
        let request = try Self.request(call, baseURL: baseURL, installation: installation)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { throw LiveRankRelayError(status: status, body: data) }
    }

    static func request(_ call: Call, baseURL: URL, installation: RelayInstallation.Credentials) throws -> URLRequest {
        var url = baseURL.appending(components: "v1", "installations", installation.id)
        var request: URLRequest
        switch call {
        case .register(let registration):
            request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.httpBody = try JSONEncoder().encode(registration)
        case .activity(let report):
            url.append(component: "activity")
            request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.httpBody = try JSONEncoder().encode(report)
        case .unregister:
            request = URLRequest(url: url)
            request.httpMethod = "DELETE"
        }
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("Bearer \(installation.secret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        return request
    }
}
