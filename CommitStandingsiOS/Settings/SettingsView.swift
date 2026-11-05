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
            // One rhythm between every section, masthead included.
            .listSectionSpacing(28)
            .inkScreen()
            .readableContentWidth()
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
                // SF, not a second ExtraBold headline under the "Settings" title.
                Text("Committed")
                    .font(.title3.weight(.semibold))
                Text("Your GitHub leaderboard, on iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A Settings action that leaves the app: white, with a soft ↗, so lime stays for what's yours
/// and what's selected.
struct OutboundLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.white)
            Image(systemName: "arrow.up.right")
                .imageScale(.small)
                .foregroundStyle(Color.soft)
                .accessibilityHidden(true)
        }
    }
}
