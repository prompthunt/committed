import SwiftUI

extension PrivateContributionsTipStyle {
    /// The iPhone's materials: a tile card, a soft icon, and a tile button rather than a lime one.
    static let committed = PrivateContributionsTipStyle(
        iconColor: .soft,
        textFont: .footnote,
        instructionColor: .soft,
        noteColor: .muted,
        spacing: 10,
        padding: 16,
        dismissTarget: 44,
        headerInset: -10,
        cardColor: .tile,
        cardStroke: .white.opacity(0.07),
        cornerRadius: 20,
        systemLink: false
    )
}

/// The Mac's private-contributions tip (`PrivateContributionsTip`: the same view, copy and
/// dismissal) in the iPhone's style.
struct PrivateWorkTip: View {
    /// Your own person view shows it always, like the Mac's About Committed.
    var dismissible = true

    var body: some View {
        PrivateContributionsTip(dismissible: dismissible)
            .environment(\.privateContributionsTipStyle, .committed)
            .buttonStyle(TileButtonStyle())
    }
}
