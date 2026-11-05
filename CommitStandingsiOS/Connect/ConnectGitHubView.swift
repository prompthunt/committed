import SwiftUI
import UIKit

/// Connect GitHub with the same device flow as the Mac. The code shows large with Copy and Open
/// GitHub buttons; nothing opens Safari on its own, so the code is visible before the hand-off.
/// Polling keeps going while the user is in Safari (see `AppModel.connectGitHub`).
struct ConnectGitHubView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthModel.self) private var auth
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedCode: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    switch auth.phase {
                    case .connecting(let userCode, let verificationURL):
                        connecting(userCode: userCode, verificationURL: verificationURL)
                    default:
                        signedOut
                    }
                    if let error = auth.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Connect GitHub")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .task(id: copiedCode) {
            guard copiedCode != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            copiedCode = nil
        }
    }

    private var signedOut: some View {
        VStack(spacing: 16) {
            Image("github-mark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text("See where you stand")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Committed ranks you against your organization members and the people you follow, by GitHub Contributions. Your list updates automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await model.connectGitHub() }
            } label: {
                Text("Connect GitHub")
                    .font(.headline)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // GitHub's own button: near-black in light mode, white in dark mode.
            .tint(colorScheme == .dark ? Color.white : Color(white: 0.13))
            Text("Read-only access to your profile, who you follow, and your organizations. Committed never sees your code.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func connecting(userCode: String, verificationURL: String) -> some View {
        VStack(spacing: 20) {
            Text("Enter this code on GitHub")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(userCode)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Code")
                .accessibilityValue(Text(userCode).speechSpellsOutCharacters())
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons(userCode: userCode, verificationURL: verificationURL) }
                VStack(spacing: 12) { buttons(userCode: userCode, verificationURL: verificationURL) }
            }
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for you to approve on GitHub…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Text("Open GitHub copies the code for you. Come back here when you’ve approved; Committed finishes on its own.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func buttons(userCode: String, verificationURL: String) -> some View {
        Button {
            copy(userCode)
        } label: {
            Label(copiedCode == userCode ? "Copied" : "Copy Code",
                  systemImage: copiedCode == userCode ? "checkmark" : "doc.on.doc")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        Button {
            copy(userCode)
            if let url = URL(string: verificationURL) { openURL(url) }
        } label: {
            Label("Open GitHub", systemImage: "safari")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func copy(_ code: String) {
        UIPasteboard.general.string = code
        copiedCode = code
    }
}
