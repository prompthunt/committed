import SwiftUI

/// The Settings tab. Each section is its own view so sections can be added without touching the
/// others. Order follows the spec: Live rank, Leaderboard Notifications, About Committed, GitHub.
/// The Mac-only items (Launch at Login, updates, Quit) don't exist on iPhone.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                LiveRankSection()
                LeaderboardNotificationsSection()
                AboutCommittedSection()
                GitHubAccountSection()
            }
            .navigationTitle("Settings")
        }
    }
}
