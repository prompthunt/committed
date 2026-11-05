import SwiftUI
import WidgetKit

/// The WidgetKit extension holds only the Live rank Live Activity (spec #39).
@main
struct LiveRankWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveRankLiveActivity()
    }
}
