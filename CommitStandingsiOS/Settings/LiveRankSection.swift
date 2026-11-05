import SwiftUI
import UIKit

/// Settings ▸ Live rank: the switch, Live rank's Window (Today by default), and a status line that
/// links to iOS Settings when Live Activities are off for Committed.
struct LiveRankSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var liveRank: LiveRankController { model.liveRank }

    var body: some View {
        Section {
            Toggle("Show Live rank", isOn: Binding(
                get: { liveRank.isEnabled },
                set: { enabled in Task { await model.liveRankSwitchChanged(enabled) } }
            ))
            if liveRank.isEnabled {
                Picker("Window", selection: Binding(
                    get: { liveRank.window },
                    set: { window in Task { await model.setLiveRankWindow(window) } }
                )) {
                    ForEach(ContributionWindow.allCases) { window in
                        Text(window.shortTitle).tag(window)
                    }
                }
            }
            if liveRank.status == .disabledInSystem {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    OutboundLabel("Open iOS Settings")
                }
            }
        } header: {
            FolioHeader("Live rank")
        } footer: {
            Text(statusText)
        }
    }

    private var statusText: String {
        switch liveRank.status {
        case .off:
            return "Turn on to keep your rank in the Dynamic Island and on the Lock Screen."
        case .waiting:
            return "Your rank appears in the Dynamic Island once your board loads with Committed open."
        case .live:
            return liveRank.isRelayConfigured
                ? "Your rank is in the Dynamic Island and on the Lock Screen. The Committed relay keeps it current, even with Committed closed."
                : "Your rank is in the Dynamic Island and on the Lock Screen. It updates when Committed refreshes."
        case .disabledInSystem:
            return "Live Activities are off for Committed in iOS Settings."
        case .failed(let message):
            return "Live rank couldn’t start: \(message)"
        }
    }
}
