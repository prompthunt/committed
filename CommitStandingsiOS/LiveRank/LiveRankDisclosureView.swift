import SwiftUI

/// Shown once before Live rank first turns on with the Committed relay: what the relay receives
/// (public usernames) and what it never receives (the GitHub token). "Not Now" leaves Live rank off.
struct LiveRankDisclosureView: View {
    @Environment(AppModel.self) private var model
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "trophy.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Keep Live rank on all day")
                        .font(.largeTitle.bold())
                    Text("To keep your rank current while Committed is closed, the Committed relay checks the public contribution graphs every 5 minutes and updates Live rank.")
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your GitHub username and the usernames on your board. These are public.",
                              systemImage: "person.2")
                        Label("Your Live rank Window and time zone, and tokens that let it update Live rank on this iPhone.",
                              systemImage: "clock")
                        Label("Never your GitHub token. That's sent only to GitHub.",
                              systemImage: "lock")
                    }
                    .font(.body)
                    Text("Turning Live rank off or disconnecting GitHub deletes this iPhone's registration from the relay.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button {
                        choose { await model.acceptLiveRankDisclosure() }
                    } label: {
                        Text("Turn On Live Rank").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("Not Now") {
                        choose { await model.declineLiveRankDisclosure() }
                    }
                }
                .disabled(isWorking)
                .padding()
                .background(.bar)
            }
            .navigationTitle("Live rank")
            .navigationBarTitleDisplayMode(.inline)
        }
        // A choice is required: dismissing by swipe would leave "never chosen" and ask again.
        .interactiveDismissDisabled()
    }

    private func choose(_ action: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }
}
