import Foundation
import Observation

/// Owns GitHub sign-in state: whether a token exists, the device-flow code to show
/// while connecting, the signed-in identity, and sign-out. Deliberately AppKit-free —
/// opening the verification URL is the View's job — so it stays unit-testable.
@Observable
@MainActor
final class AuthModel {
    enum Phase: Equatable {
        case signedOut
        case connecting(userCode: String, verificationURL: String)
        case signedIn
    }

    private(set) var phase: Phase
    private(set) var username: String?
    /// The signed-in user's GitHub display name (the profile `name` field), when set. Held in
    /// memory only and re-fetched per launch via `refreshIdentity()` — not persisted. nil when
    /// unknown (not yet fetched, fetch failed, or the profile has no name).
    private(set) var displayName: String?
    private(set) var errorMessage: String?
    private let credentials: GitHubCredentialStoring
    private let auth: GitHubAuth
    private let accountFactory: @Sendable (String) -> GitHubAccountClient
    /// Called after a successful sign-in with the resolved username (when known) so the
    /// caller can seed "you" and refresh.
    private let onSignedOut: @MainActor () -> Void
    private let onSignedIn: @MainActor (String?) async -> Void

    init(
        credentials: GitHubCredentialStoring,
        auth: GitHubAuth,
        accountFactory: @escaping @Sendable (String) -> GitHubAccountClient = { GitHubAccountClient(token: $0) },
        onSignedIn: @escaping @MainActor (String?) async -> Void = { _ in },
        onSignedOut: @escaping @MainActor () -> Void = {}
    ) {
        self.credentials = credentials
        self.auth = auth
        self.accountFactory = accountFactory
        self.onSignedIn = onSignedIn
        self.onSignedOut = onSignedOut
        self.phase = credentials.read() != nil ? .signedIn : .signedOut
    }

    var isSignedIn: Bool {
        if case .signedIn = phase { return true }
        return false
    }

    /// Run the full device-flow sign-in: request a code, expose it for the UI, poll for
    /// the token, persist it, fetch the identity, and notify the caller.
    func signIn() async {
        errorMessage = nil
        switch await auth.requestDeviceCode() {
        case .failure(let error):
            errorMessage = "Couldn’t connect to GitHub: \(message(for: error))"
        case .success(let code):
            phase = .connecting(userCode: code.userCode, verificationURL: code.verificationUri)
            switch await auth.pollForToken(deviceCode: code.deviceCode, interval: code.interval, expiresIn: code.expiresIn) {
            case .failure(let error):
                errorMessage = message(for: error)
                phase = .signedOut
            case .success(let token):
                credentials.save(token)
                let profile = await accountFactory(token).currentUserProfile()
                username = profile?.login
                displayName = profile?.name
                // Approval is complete. Let the board show sync progress immediately.
                phase = .signedIn
                await onSignedIn(username)
            }
        }
    }

    /// Re-fetch the signed-in user's login + display name. Called on launch/first-open so the
    /// hero can show a real first name even on a relaunch (where `signIn()` never ran this
    /// session). No-op when signed out or the fetch fails; never touches `phase`.
    func refreshIdentity() async {
        guard isSignedIn, let token = credentials.read() else { return }
        guard let profile = await accountFactory(token).currentUserProfile(),
              isSignedIn, credentials.read() == token else { return }
        username = profile.login
        displayName = profile.name
    }

    func signOut() {
        credentials.clear()
        username = nil
        displayName = nil
        errorMessage = nil
        phase = .signedOut
        onSignedOut()
    }

    private func message(for error: GitHubAuth.AuthError) -> String {
        switch error {
        case .network(let m): return "Network error: \(m)"
        case .parseFailed(let m): return "Unexpected response: \(m)"
        case .denied: return "The GitHub connection was declined."
        case .expired: return "The code expired. Try again."
        case .unexpected(let m): return "Couldn’t connect to GitHub: \(m)"
        }
    }
}
