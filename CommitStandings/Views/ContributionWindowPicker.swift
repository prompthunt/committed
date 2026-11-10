import SwiftUI

/// The Today / 7 days / 30 days / This month Window switch, shared by the Mac popover and the iPhone board.
struct ContributionWindowPicker: View {
    @Environment(StandingsStore.self) private var store

    var body: some View {
        @Bindable var store = store

        Picker("Contribution window", selection: $store.selectedWindow) {
            ForEach(ContributionWindow.allCases) { window in
                Text(window.shortTitle).tag(window)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
