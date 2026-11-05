import SwiftUI

// People and Settings are built in #42. These keep the tab structure in place until then.

struct PeoplePlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "People",
                systemImage: "person.2",
                description: Text("Reviewing and hiding people arrives in a later build.")
            )
            .navigationTitle("People")
        }
    }
}

struct SettingsPlaceholderView: View {
    @Environment(AuthModel.self) private var auth
    @State private var confirmingDisconnect = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Disconnect GitHub", role: .destructive) {
                        confirmingDisconnect = true
                    }
                } footer: {
                    Text("More settings arrive in a later build.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Disconnect GitHub?", isPresented: $confirmingDisconnect) {
                Button("Disconnect GitHub", role: .destructive) { auth.signOut() }
            } message: {
                Text("Committed deletes your token from this iPhone.")
            }
        }
    }
}
