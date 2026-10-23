import Foundation

/// GitHub OAuth **Device Flow** client — the no-backend, no-client-secret way for a
/// native desktop app to obtain a user token. The app shows `userCode`, the user
/// approves it at `verificationUri`, and the app polls until a token is issued.
///
/// Prerequisite: a registered GitHub OAuth app whose public client ID is set in
/// `GitHubAuth.clientID` (see `Config`). Without a real client ID the requests will
/// be rejected by GitHub — the flow is otherwise complete.
struct GitHubAuth: Sendable {
    let clientID: String
    let scope: String
    private let session: URLSession
    private let baseURL: URL
    private let sleep: @Sendable (UInt64) async -> Void
    private let now: @Sendable () -> Date

    init(
        clientID: String,
        scope: String = "read:org read:user",
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://github.com")!,
        sleep: @escaping @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientID = clientID
        self.scope = scope
        self.session = session
        self.baseURL = baseURL
        self.sleep = sleep
        self.now = now
    }

    /// Max consecutive transient transport errors tolerated mid-poll before giving up.
    private static let maxTransientErrors = 5

    struct DeviceCode: Decodable, Sendable, Equatable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let expiresIn: Int
        let interval: Int
    }

    enum AuthError: Error, Equatable {
        case network(String)
        case parseFailed(String)
        case denied
        case expired
        case unexpected(String)
    }

    /// Step 1: request a device + user code.
    func requestDeviceCode() async -> Result<DeviceCode, AuthError> {
        var request = URLRequest(url: baseURL.appendingPathComponent("login/device/code"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["client_id": clientID, "scope": scope])
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .failure(.network("device code request failed"))
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return .success(try decoder.decode(DeviceCode.self, from: data))
        } catch let urlError as URLError {
            return .failure(.network(urlError.localizedDescription))
        } catch {
            return .failure(.parseFailed(error.localizedDescription))
        }
    }

    /// Step 2: poll for the access token, honoring `authorization_pending`,
    /// `slow_down`, `expired_token`, and `access_denied`. Returns the token string.
    ///
    /// Bounded three ways so it can never spin forever: a client-side deadline derived
    /// from `expiresIn`, cooperative cancellation, and a cap on consecutive transient
    /// transport errors (a single dropped poll no longer aborts a valid attempt).
    func pollForToken(deviceCode: String, interval: Int, expiresIn: Int) async -> Result<String, AuthError> {
        var currentInterval = max(1, interval)
        let deadline = now().addingTimeInterval(TimeInterval(expiresIn))
        var consecutiveTransportErrors = 0
        while true {
            if Task.isCancelled { return .failure(.network("cancelled")) }
            if now() >= deadline { return .failure(.expired) }
            await sleep(UInt64(currentInterval) * 1_000_000_000)
            switch await requestToken(deviceCode: deviceCode) {
            case .token(let token):
                return .success(token)
            case .pending:
                consecutiveTransportErrors = 0
                continue
            case .slowDown:
                currentInterval = min(currentInterval + 5, 60) // honor backoff, but cap it
                consecutiveTransportErrors = 0
                continue
            case .expired:
                return .failure(.expired)
            case .denied:
                return .failure(.denied)
            case .failure(let message):
                return .failure(.unexpected(message))
            case .transport(let message):
                // Transient: a dropped poll shouldn't kill an otherwise-valid attempt.
                consecutiveTransportErrors += 1
                if consecutiveTransportErrors >= Self.maxTransientErrors {
                    return .failure(.network(message))
                }
                continue
            }
        }
    }

    private enum TokenPollResult {
        case token(String)
        case pending
        case slowDown
        case expired
        case denied
        case failure(String)
        case transport(String)
    }

    private func requestToken(deviceCode: String) async -> TokenPollResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("login/oauth/access_token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])
        request.timeoutInterval = 15
        do {
            let (data, _) = try await session.data(for: request)
            let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
            if let token = payload.accessToken { return .token(token) }
            switch payload.error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown
            case "expired_token": return .expired
            case "access_denied": return .denied
            case .some(let other): return .failure(other)
            case nil: return .failure("no token and no error")
            }
        } catch let urlError as URLError {
            return .transport(urlError.localizedDescription)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let error: String?
        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case error
        }
    }

    private func form(_ pairs: [String: String]) -> Data {
        let encoded = pairs.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }
}
