import SwiftUI
import UIKit

/// Connect GitHub with the same device flow as the Mac. The code shows large with Copy and Open
/// GitHub buttons; nothing opens Safari on its own, so the code is visible before the hand-off.
/// Polling keeps going while the user is in Safari (see `AppModel.connectGitHub`).
struct ConnectGitHubView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthModel.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var copiedCode: String?
    /// A readable column that grows with Dynamic Type instead of a fixed width.
    @ScaledMetric(relativeTo: .body) private var readableWidth: CGFloat = 520

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    switch auth.phase {
                    case .connecting(let userCode, let verificationURL):
                        connecting(userCode: userCode, verificationURL: verificationURL)
                    default:
                        signedOut
                    }
                    if let error = auth.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(Color.warning)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 24)
                .frame(maxWidth: readableWidth)
                // Partially folded like a book, the centered column would put Connect GitHub in
                // the fold; it moves to one side instead.
                .avoidingFold()
            }
            .scrollBounceBehavior(.basedOnSize)
            .background {
                // The site's hero: a lit field of contribution squares, kept dim behind the text.
                ZStack(alignment: .top) {
                    Color.ink
                    AnimatedSquareField(light: UnitPoint(x: 0.5, y: 0.05), reach: 0.75, cell: 22, tone: .connect)
                        .frame(height: 460)
                        .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                }
                .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The site header's wordmark rather than a title that repeats the button.
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        TrophyMark(size: 17)
                        Text("Committed").font(.headline)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Committed")
                    .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .interactiveDismissDisabled()
        .task(id: copiedCode) {
            guard copiedCode != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            copiedCode = nil
        }
    }

    private var signedOut: some View {
        VStack(spacing: 18) {
            AppMark(size: 76)
                .padding(.bottom, 6)
            // The site's headline, with its lime emphasis.
            Text("Who shipped more \(Text("today?").foregroundStyle(Color.lime))")
                .font(CommittedType.display(46, relativeTo: .largeTitle))
                .displayTracking(46)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Rank against your organization and the people you follow, by GitHub Contributions.")
                .font(.body)
                .foregroundStyle(Color.soft)
                .multilineTextAlignment(.center)
            Button {
                Task { await model.connectGitHub() }
            } label: {
                Label {
                    Text("Connect GitHub")
                } icon: {
                    Image("github-mark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
            }
            .buttonStyle(LimeButtonStyle())
            .padding(.top, 8)
            Text("Read-only access to your profile, who you follow, and your organizations. Committed never sees your code.")
                .font(.footnote)
                // Soft, not muted: the field can reach this far down.
                .foregroundStyle(Color.soft)
                .multilineTextAlignment(.center)
        }
    }

    private func connecting(userCode: String, verificationURL: String) -> some View {
        VStack(spacing: 22) {
            Text("Enter this code on GitHub")
                .font(CommittedType.display(30, relativeTo: .title))
                .displayTracking(30)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(userCode)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .foregroundStyle(Color.lime)
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)
                .padding(.vertical, 22)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(Color.tile, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.lime.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: Color.lime.opacity(0.18), radius: 24, y: 10)
                .accessibilityLabel("Code")
                .accessibilityValue(Text(userCode).speechSpellsOutCharacters())
            VStack(spacing: 12) { buttons(userCode: userCode, verificationURL: verificationURL) }
            HStack(spacing: 8) {
                ProgressView().tint(.lime)
                Text("Waiting for you to approve on GitHub…")
                    .font(.subheadline)
                    .foregroundStyle(Color.soft)
            }
            .accessibilityElement(children: .combine)
            Text("Open GitHub copies the code for you. Come back here when you’ve approved; Committed finishes on its own.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func buttons(userCode: String, verificationURL: String) -> some View {
        Button {
            copy(userCode)
            if let url = URL(string: verificationURL) { openURL(url) }
        } label: {
            Label("Open GitHub", systemImage: "safari")
                .lineLimit(1)
        }
        .buttonStyle(LimeButtonStyle())
        Button {
            copy(userCode)
        } label: {
            Label(copiedCode == userCode ? "Copied" : "Copy Code",
                  systemImage: copiedCode == userCode ? "checkmark" : "doc.on.doc")
                .lineLimit(1)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(TileButtonStyle())
    }

    private func copy(_ code: String) {
        UIPasteboard.general.string = code
        copiedCode = code
    }
}
