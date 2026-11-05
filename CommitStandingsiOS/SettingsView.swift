import SwiftUI
import UIKit

/// The Settings tab, top to bottom: Leaderboard Notifications, Live rank (#43), About
/// Committed, and your account with Disconnect GitHub. Mac-only items (Launch at Login,
/// updates, Quit) don't exist on iPhone.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                LeaderboardNotificationsSection()

                // MARK: Live rank (#43)
                // LiveRankSettingsSection() goes here, between Leaderboard Notifications and About.

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Committed", systemImage: "info.circle")
                    }
                }

                AccountSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The switch asks for iOS permission when turned on and turns itself back off when that's
/// denied. Crossings are checked whenever Committed refreshes while it's open.
private struct LeaderboardNotificationsSection: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var isOn = false
    @State private var isRequesting = false
    @State private var blockedInSettings = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { isOn }, set: setEnabled)) {
                Label("Leaderboard Notifications", systemImage: "bell.badge")
            }
            .disabled(isRequesting)
            if blockedInSettings {
                Button("Open iOS Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
        } footer: {
            if blockedInSettings {
                Text("Notifications are off for Committed in iOS Settings, so nothing will arrive.")
            } else {
                Text("Hear when someone passes you, or you pass them. Committed checks whenever it refreshes while open.")
            }
        }
        // Re-read on return from iOS Settings, where permission may have changed.
        .task(id: scenePhase) { await reload() }
    }

    private func setEnabled(_ enabled: Bool) {
        isOn = enabled
        isRequesting = enabled
        Task {
            isOn = await notifications.setEnabled(enabled)
            isRequesting = false
            await reload()
        }
    }

    private func reload() async {
        isOn = notifications.isEnabled
        blockedInSettings = isOn ? !(await notifications.isAuthorized()) : false
    }
}

/// Who's connected, and Disconnect GitHub (with a confirmation).
private struct AccountSection: View {
    @Environment(AppModel.self) private var app
    @State private var confirmingDisconnect = false

    var body: some View {
        Section {
            if let username = app.store.selfCompetitor?.username ?? app.auth.username {
                LabeledContent("GitHub account", value: "@\(username)")
            }
            Button("Disconnect GitHub", role: .destructive) {
                confirmingDisconnect = true
            }
            .confirmationDialog("Disconnect GitHub?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
                Button("Disconnect GitHub", role: .destructive) { app.disconnect() }
            } message: {
                Text("Committed deletes your token from this iPhone. Your choices in People are kept for when you reconnect.")
            }
        } footer: {
            Text("Committed uses your token only to talk to GitHub, and it’s stored in this iPhone’s Keychain.")
        }
    }
}

/// About Committed: how Contributions are counted (the Mac's explainer copy) and the version.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ContributionsExplainer()
                Text(version)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationTitle("About Committed")
        .navigationBarTitleDisplayMode(.inline)
    }
}
