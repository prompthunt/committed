import SwiftUI
import UIKit

/// Connect GitHub with the device flow: show the code large, copy it, open GitHub's page,
/// and keep polling while the user approves in Safari. `AuthModel` (shared with the Mac)
/// runs the flow; this view only presents it.
///
/// Unlike the Mac, Safari doesn't open by itself when the code appears: on a phone that would
/// pull the user away before they can copy the code.
struct ConnectView: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch auth.phase {
                    case .connecting(let userCode, let verificationURL):
                        DeviceCodePanel(userCode: userCode, verificationURL: verificationURL)
                    case .signedOut, .signedIn:
                        Welcome()
                    }
                    if let error = auth.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Committed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct Welcome: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(.largeTitle))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("See where you stand")
                .font(.title2.weight(.semibold))
            Text("Rank your GitHub Contributions against the people you follow and your organization members. Your board updates automatically.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await auth.signIn() }
            } label: {
                Label {
                    Text("Connect GitHub")
                } icon: {
                    Image("github-mark").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 18, height: 18)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Read-only access to your profile, who you follow, and your organizations. Committed never sees your code, and your token stays in this iPhone's Keychain.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct DeviceCodePanel: View {
    let userCode: String
    let verificationURL: String
    @Environment(\.openURL) private var openURL
    @State private var copyID: UUID?

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter this code on GitHub")
                .font(.headline)
            Text(userCode)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .textSelection(.enabled)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel("Code \(userCode.map(String.init).joined(separator: " "))")
            VStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = userCode
                    copyID = UUID()
                } label: {
                    Label(copyID == nil ? "Copy Code" : "Copied",
                          systemImage: copyID == nil ? "doc.on.doc" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    if let url = URL(string: verificationURL) { openURL(url) }
                } label: {
                    Label("Open GitHub", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for approval…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Text("After you approve on GitHub, come back here. Committed finishes connecting on its own.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .task(id: copyID) {
            guard copyID != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copyID = nil }
        }
    }
}

#Preview("Signed out") {
    let app = AppModel(.testHost())
    ConnectView().environment(app.auth)
}
