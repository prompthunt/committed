import SwiftUI
import WidgetKit

/// The Live rank extension holds only the Live Activity; Committed has no Home Screen widgets.
@main
struct LiveRankWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveRankLiveActivity()
    }
}
