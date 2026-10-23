import SwiftUI

/// First-run gate: "Connect GitHub" → device-flow code → polling. Opens the
/// verification URL automatically when the code appears, with a manual button +
/// copy-to-clipboard as backup.
struct SignInView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var copyID: UUID?

    private var copied: Bool { copyID != nil }

    var body: some View {
        VStack(spacing: 12) {
            switch auth.phase {
            case .signedOut:
                Image("github-mark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.primary)
                Text("Committed")
                    .font(.headline)
                Text("See your standings alongside your organization members and people you follow. Your list updates automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await auth.signIn() }
                } label: {
                    GitHubButtonLabel(title: "Connect GitHub")
                }
                .buttonStyle(GitHubButtonStyle())
                Text("Read-only access to your profile, who you follow, and your organizations. Committed never sees your code.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

            case .connecting(let userCode, let verificationURL):
                Text("Enter this code at github.com/login/device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Text(userCode)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .textSelection(.enabled)
                    Button {
                        copyCode(userCode)
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy code")
                    .accessibilityLabel(copied ? "Code copied" : "Copy verification code")
                }
                .padding(.vertical, 2)
                Button("Open github.com/login/device") {
                    open(verificationURL)
                }
                .buttonStyle(.bordered)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("waiting for approval…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            case .signedIn:
                EmptyView()
            }

            if let error = auth.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .task(id: copyID) {
            guard copyID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1.5))
                copyID = nil
            } catch {
                // A new copy or a disappearing view cancels this feedback timer.
            }
        }
        .onChange(of: auth.phase) { _, newPhase in
            if case .connecting(_, let url) = newPhase { open(url) }
        }
    }

    private func copyCode(_ code: String) {
        if MacSystem.copy(code) { copyID = UUID() }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }
}

/// GitHub-style button content: logo + label.
private struct GitHubButtonLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image("github-mark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text(title).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Solid black/white button (no accent color), inverting with the color scheme so it
/// always contrasts the panel: near-black in light mode, white in dark mode.
private struct GitHubButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = scheme == .dark ? .white : Color(white: 0.13)
        let fg: Color = scheme == .dark ? .black : .white
        configuration.label
            .foregroundStyle(fg)
            .background(fill.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
