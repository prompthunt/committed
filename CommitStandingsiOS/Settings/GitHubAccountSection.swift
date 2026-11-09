import SwiftUI

/// Connected account and Disconnect GitHub. Disconnecting deletes the token from this iPhone's
/// Keychain and clears the board; Connect GitHub comes back because `RootView` presents it
/// whenever no account is connected. Hide/show choices stay saved for when you reconnect.
///
/// On the Sample board there's no account to disconnect: Connect GitHub replaces it with your real
/// board, and Leave Sample Board returns to the Connect GitHub screen.
struct GitHubAccountSection: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthModel.self) private var auth
    @State private var confirmingDisconnect = false

    var body: some View {
        if model.mode == .sampleBoard {
            sampleBoard
        } else {
            connected
        }
    }

    private var connected: some View {
        Section {
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
        } header: {
            FolioHeader("GitHub")
        }
    }

    private var sampleBoard: some View {
        Section {
            Button {
                Task { await model.connectGitHub() }
            } label: {
                Text("Connect GitHub")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.lime)
            }
            Button {
                Task { await model.leaveSampleBoard() }
            } label: {
                Text("Leave Sample Board")
                    .foregroundStyle(.white)
            }
        } header: {
            FolioHeader("GitHub")
        } footer: {
            Text("You're on the sample board: built-in people and counts, and nothing leaves this iPhone. Connect GitHub to see your real board.")
        }
    }
}
