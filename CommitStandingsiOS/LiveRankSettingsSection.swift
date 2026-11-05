import SwiftUI
import UIKit

/// Settings ▸ Live rank: the switch, the Window it follows (Today by default), and what's
/// happening, with a way to iOS Settings when Live Activities are off there.
struct LiveRankSettingsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        let liveRank = app.liveRank
        Section {
            Toggle("Live rank", systemImage: "trophy", isOn: Binding(
                get: { liveRank.isEnabled },
                set: { enabled in Task { await app.setLiveRankEnabled(enabled) } }
            ))
            if liveRank.isEnabled {
                Picker("Window", systemImage: "calendar", selection: Binding(
                    get: { liveRank.window },
                    set: { window in Task { await app.setLiveRankWindow(window) } }
                )) {
                    ForEach(ContributionWindow.allCases) { window in
                        Text(window.shortTitle).tag(window)
                    }
                }
            }
            if liveRank.status == .disabledInSystem {
                Button("Open iOS Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Live rank")
        } footer: {
            Text(Self.statusText(liveRank.status, window: liveRank.window, usesRelay: liveRank.usesRelay))
        }
    }

    static func statusText(_ status: LiveRankController.Status, window: ContributionWindow, usesRelay: Bool = false) -> String {
        switch status {
        case .off:
            usesRelay
                ? "Keep your rank in the Dynamic Island and on the Lock Screen, updated by the Committed relay while Committed is closed. The relay receives your username and the usernames on your board, never your GitHub token."
                : "Keep your rank in the Dynamic Island and on the Lock Screen."
        case .waiting:
            "Live rank appears the next time Committed is open with your board loaded."
        case .live:
            usesRelay
                ? "Your rank for \(window.accessibilityDescription) is in the Dynamic Island and on the Lock Screen. The Committed relay keeps it current while Committed is closed."
                : "Your rank for \(window.accessibilityDescription) is in the Dynamic Island and on the Lock Screen. It updates when Committed refreshes."
        case .disabledInSystem:
            "Live Activities are off for Committed in iOS Settings. Turn them on to see Live rank."
        case .failed(let message):
            "Live rank couldn't start: \(message)"
        }
    }
}
