import SwiftUI

/// Before Live rank first turns on with a Committed relay: what the relay receives, and what it
/// never does. Shown once the board is here if the person hasn't decided, and from the Settings
/// switch until it's accepted. Two explicit choices; swiping it away isn't one of them.
struct LiveRankDisclosureSheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "trophy.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Keep Live rank on all day")
                        .font(.title.bold())
                    Text("Live rank shows your rank in the Dynamic Island and on the Lock Screen. To keep it current while Committed is closed, the Committed relay checks the board every 5 minutes and updates it for you.")
                    VStack(alignment: .leading, spacing: 12) {
                        Text("The relay receives")
                            .font(.headline)
                        Label("Your GitHub username", systemImage: "person.crop.circle")
                        Label("The usernames on your board", systemImage: "person.2")
                        Label("Your Live rank Window and time zone", systemImage: "clock")
                        Label("A push token for Live rank on this iPhone", systemImage: "iphone")
                    }
                    Text("Usernames and contribution counts are public on GitHub. The relay never receives your GitHub token, which is sent only to GitHub. Turning Live rank off or disconnecting GitHub deletes this iPhone's data from the relay.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        Task { await app.acceptLiveRankDisclosure() }
                    } label: {
                        Text("Turn On Live rank").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("Not Now") { app.declineLiveRankDisclosure() }
                        .controlSize(.large)
                }
                .padding()
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
    }
}

extension View {
    /// Presents the Live rank relay disclosure when `LiveRankController` asks for it.
    func liveRankDisclosure() -> some View {
        modifier(LiveRankDisclosurePresenter())
    }
}

private struct LiveRankDisclosurePresenter: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { app.liveRank.isPresentingDisclosure },
            set: { presented in if !presented, app.liveRank.isPresentingDisclosure { app.declineLiveRankDisclosure() } }
        )) {
            LiveRankDisclosureSheet()
        }
    }
}
