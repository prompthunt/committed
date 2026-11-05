import SwiftUI

/// Standalone explainer for the Contributions metric, hosted in its own window (opened from
/// the board card or the ⋯ menu). The copy itself is `ContributionsExplainer`, shared with
/// the iPhone's About Committed screen.
struct ContributionsExplainerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ContributionsExplainer()

            HStack {
                Spacer()
                Button("Got it") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
    }
}
