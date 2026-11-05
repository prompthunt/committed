import SwiftUI

/// The Settings tab. #42 adds Leaderboard Notifications and About Committed, and #43 adds the Live
/// rank section above Account. Add each as its own `Section` in this `Form`.
struct SettingsView: View {
    @Environment(AuthModel.self) private var auth
    @State private var confirmingDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub") {
                    if let username = auth.username {
                        LabeledContent("Connected as", value: "@\(username)")
                    }
                    Button("Disconnect GitHub", role: .destructive) {
                        confirmingDisconnect = true
                    }
                    .confirmationDialog(
                        "Disconnect GitHub?", isPresented: $confirmingDisconnect, titleVisibility: .visible
                    ) {
                        Button("Disconnect", role: .destructive) { auth.signOut() }
                    } message: {
                        Text("This deletes your GitHub token from this iPhone and clears your board.")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
