import ActivityKit
import SwiftUI
import WidgetKit

/// Stand-in attributes so the extension has a Live Activity to register. The real contract,
/// `LiveRankAttributes`, lives in shared code and replaces this in the on-device Live rank
/// ticket (#43).
struct LiveRankPlaceholderAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}
}

/// Empty Live Activity: every presentation is blank until the Live rank views land.
struct LiveRankLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveRankPlaceholderAttributes.self) { _ in
            EmptyView()
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { EmptyView() }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
        }
    }
}
