import SwiftUI

/// The ⋯ overflow, rendered inline as a grouped card: app actions (About / Refresh / Check for
/// Updates / Automatic Updates / Launch at Login), then People, then account (Log out / Quit).
/// Tapping an action dismisses via `close`; the preference toggles leave it open.
struct OverflowMenu: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(AuthModel.self) private var auth
    @Environment(\.openWindow) private var openWindow
    let updater: AppUpdater
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // App
            MenuRow(title: "About \(HeaderBar.appName)", action: act { ExplainerWindow.open(openWindow) })
            if auth.isSignedIn, store.hasSelf {
                MenuRow(title: "Refresh", trailing: lastUpdatedText,
                        enabled: !refresh.isRefreshing,
                        action: act { Task { await refresh.refreshAll(reason: .manual) } })
            }
            if updater.updateAvailable, let version = updater.latestVersion {
                MenuRow(title: "Update to \(version)…", action: act { updater.installUpdate() })
            } else {
                MenuRow(title: "Check for Updates…", enabled: updater.canCheckForUpdates,
                        action: act { updater.checkForUpdates() })
            }
            Toggle("Automatic Updates", isOn: Binding(
                get: { updater.automaticallyDownloadsUpdates },
                set: { updater.setAutomaticUpdates($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .help("Download updates in the background and install when Committed quits")
            LaunchAtLoginRow()
            if auth.isSignedIn, store.hasSelf {
                NotifyRow()
            }

            // Board — manage the list in the Committed window.
            if auth.isSignedIn, store.hasSelf {
                MenuDivider()
                MenuRow(title: "People…", action: act { FullRankingsWindow.open(openWindow) })
            }

            // Account + quit
            MenuDivider()
            if auth.isSignedIn {
                MenuRow(title: "Log out", action: act { auth.signOut() })
            }
            MenuRow(title: "Quit \(HeaderBar.appName)", action: act { MacSystem.quit() })
        }
        .padding(6)
        .frame(width: 260)
        .modifier(OverflowSurface())
    }

    /// Dismiss the overflow first, then run the action (matches native menu behavior).
    private func act(_ work: @escaping () -> Void) -> () -> Void { { close(); work() } }

    private var lastUpdatedText: String? {
        if refresh.isRefreshing { return "updating…" }
        guard let last = store.lastUpdated else { return nil }
        return RelativeTimeFormatter.short(from: last, to: Date())
    }
}

/// A tappable overflow row with a subtle hover highlight and an optional trailing label.
private struct MenuRow: View {
    let title: String
    var trailing: String? = nil
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(hovering && enabled ? 0.1 : 0))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}

/// Use native checkbox toggles in the inline menu. These provide keyboard and VoiceOver
/// semantics without the switch rendering issue this popover previously worked around.
private struct LaunchAtLoginRow: View {
    @State private var isOn = LoginItem.isEnabled

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { isOn },
            set: { enabled in
                LoginItem.setEnabled(enabled)
                // Registration can fail or require approval in System Settings.
                isOn = LoginItem.isEnabled
            }
        ))
        .toggleStyle(.checkbox)
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .onAppear { isOn = LoginItem.isEnabled }
    }
}

/// Persist the preference and reconcile it with the system permission result. Disable the
/// control while the prompt is pending so repeated clicks cannot race authorization requests.
private struct NotifyRow: View {
    @Environment(NotificationService.self) private var notifications
    @AppStorage(NotificationService.enabledDefaultsKey) private var isOn = false
    @State private var requestingAuthorization = false

    var body: some View {
        Toggle("Leaderboard Notifications", isOn: Binding(
            get: { isOn },
            set: { enabled in
                isOn = enabled
                guard enabled else { return }
                requestingAuthorization = true
                Task {
                    if await notifications.requestAuthorization() == false { isOn = false }
                    requestingAuthorization = false
                }
            }
        ))
        .toggleStyle(.checkbox)
        .disabled(requestingAuthorization)
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

/// Thin inset divider between groups in the overflow card. An explicit light hairline —
/// SwiftUI's `Divider()` renders dark against the card's material.
private struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
    }
}


/// Liquid Glass belongs to the floating controls, rather than the scrolling board.
private struct OverflowSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(.background, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.6), lineWidth: 1)
                }
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }
}
