import SwiftUI

/// Status also lives on the board so an offline or permission failure is never hidden.
struct RosterStatusView: View {
    @Environment(GitHubRoster.self) private var roster
    @Environment(RefreshCoordinator.self) private var refresh

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if roster.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Syncing people from GitHub…")
                }
            } else if let error = roster.errorMessage {
                Text(error).foregroundStyle(.orange)
                HStack {
                    Text(roster.snapshot == nil ? "Your saved list hasn’t changed." : "Showing your last synced people.")
                    Button("Retry") { Task { await refresh.refreshAll(reason: .manual) } }
                        .disabled(refresh.isRefreshing)
                }
            } else if let snapshot = roster.snapshot {
                Text("Synced \(snapshot.updatedAt, style: .relative) ago")
                if let notice = snapshot.restrictedNotice {
                    Text(notice)
                }
            } else {
                Text("Your people will sync from GitHub automatically.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
