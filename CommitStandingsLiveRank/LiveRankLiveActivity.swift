import ActivityKit
import SwiftUI
import WidgetKit

/// Placeholder attributes so the extension has an `ActivityConfiguration` to host.
/// Ticket #43 replaces this with the spec's `LiveRankAttributes` (static `selfLogin`,
/// `ContentState` = the shared `LiveRankState`) and deletes this type.
struct LiveRankPlaceholderAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}
}

/// Empty Live rank Live Activity: every presentation is blank until #43 designs them.
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
