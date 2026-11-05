import SwiftUI
import UIKit
import UserNotifications

/// Leaderboard Notifications: a crossing notification when someone passes you or you pass them,
/// checked on every refresh. Turning it on shows the iOS permission prompt and switches back off
/// if permission is denied. If iOS Settings has notifications off for Committed, the footer says
/// so and links there.
struct LeaderboardNotificationsSection: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NotificationService.enabledDefaultsKey) private var isOn = false
    @State private var requestingAuthorization = false
    @State private var deniedInSettings = false

    var body: some View {
        Section {
            Toggle("Leaderboard Notifications", isOn: Binding(
                get: { isOn },
                set: { enabled in
                    isOn = enabled
                    guard enabled else { return }
                    requestingAuthorization = true
                    Task {
                        await notifications.setEnabled(true)
                        requestingAuthorization = false
                        await checkSystemSetting()
                    }
                }
            ))
            .disabled(requestingAuthorization)
        } header: {
            FolioHeader("Notifications")
        } footer: {
            if deniedInSettings {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications for Committed are off in iOS Settings.")
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        OutboundLabel("Open Settings")
                    }
                    .font(.footnote.weight(.semibold))
                }
            } else {
                Text("Get notified when someone passes you or you pass them.")
            }
        }
        .task { await checkSystemSetting() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await checkSystemSetting() } }
        }
    }

    private func checkSystemSetting() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        deniedInSettings = status == .denied
    }
}
