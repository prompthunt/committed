import SwiftUI

/// Shown once before Live rank first turns on with the Committed relay: what the relay receives
/// (public usernames) and what it never receives (the GitHub token). "Not Now" leaves Live rank off.
struct LiveRankDisclosureView: View {
    @Environment(AppModel.self) private var model
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Keep Live rank on all day")
                        .font(.title.bold())
                    Text("The Committed relay checks public contribution graphs every 5 minutes and updates Live rank, even with Committed closed.")
                    VStack(alignment: .leading, spacing: 12) {
                        Label("It receives your GitHub username and the usernames on your board. These are public.",
                              systemImage: "person.2")
                        Label("It never receives your GitHub token. That's sent only to GitHub.",
                              systemImage: "lock")
                        Label("It also gets your Live rank Window, time zone, and the tokens that update Live rank on this iPhone.",
                              systemImage: "clock")
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
