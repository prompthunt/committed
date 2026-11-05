import SwiftUI

/// Connected account and Disconnect GitHub. Disconnecting deletes the token from this iPhone's
/// Keychain and clears the board; Connect GitHub comes back because `RootView` presents it
/// whenever no account is connected. Hide/show choices stay saved for when you reconnect.
struct GitHubAccountSection: View {
    @Environment(AuthModel.self) private var auth
    @State private var confirmingDisconnect = false

    var body: some View {
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
                Text("This deletes your GitHub token from this iPhone and clears your board. Who you've hidden stays saved for when you reconnect.")
            }
        }
    }
}
