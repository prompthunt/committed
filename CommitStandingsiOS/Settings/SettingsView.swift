import SwiftUI

/// The Settings tab. Each section is its own view so sections can be added without touching the
/// others. Order follows the spec: Live rank, Leaderboard Notifications, About Committed, GitHub.
/// The Mac-only items (Launch at Login, updates, Quit) don't exist on iPhone.
///
/// Still a grouped `Form` (settings-shaped content stays native), set on the ink page with the
/// site's tile rows and hairlines.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section { SettingsMasthead() }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                Group {
                    LiveRankSection()
                    LeaderboardNotificationsSection()
                    AboutCommittedSection()
                    GitHubAccountSection()
                }
                .listRowBackground(Color.tile)
                .listRowSeparatorTint(.hairline)
            }
            .inkScreen()
            .navigationTitle("Settings")
        }
    }
}

/// The app's mark and name at the top of Settings, like the site's header.
private struct SettingsMasthead: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 60

    var body: some View {
        HStack(spacing: 14) {
            AppMark(size: iconSize, glows: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("Committed")
                    .font(CommittedType.display(28, relativeTo: .title))
                    .displayTracking(28)
                Text("Your GitHub leaderboard, on iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
