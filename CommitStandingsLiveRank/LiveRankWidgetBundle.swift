import SwiftUI
import WidgetKit

/// The Live rank extension: the Live Activity, and Committed's Home Screen and Lock Screen widgets.
@main
struct LiveRankWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveRankLiveActivity()
        CommittedWidget()
    }
}
