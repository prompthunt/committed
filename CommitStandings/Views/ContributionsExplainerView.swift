import SwiftUI

/// Standalone explainer for the Contributions metric, hosted in its own window on the Mac (opened
/// from the board card or the ⋯ menu). The iPhone shows the same `ContributionsExplainerContent`
/// on its About Committed page.
struct ContributionsExplainerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ContributionsExplainerContent()

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

/// What a contribution is, shared by the Mac explainer window and iPhone's About Committed. Kept
/// self-contained and static — a scannable icon-per-row breakdown of what GitHub actually counts,
/// so friends stop conflating it with commits/LOC.
struct ContributionsExplainerContent: View {
    // Fixed 16 pt on the Mac (no Dynamic Type there); scales with text size on iPhone.
    @ScaledMetric(relativeTo: .callout) private var iconSize = 16
    @ScaledMetric(relativeTo: .callout) private var iconWidth = 24
    @ScaledMetric(relativeTo: .callout) private var iconHeight = 22

    private struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        let label: String
        let detail: String
    }

    // Plain-language rows for non-technical friends: a human label for what you did, with the
    // real GitHub term kept as a quiet footnote so developers still trust the breakdown. Icons
    // are meaning-first (what the action *is*), not the git jargon.
    private let items: [Item] = [
        Item(symbol: "square.and.pencil", label: "You saved your work", detail: "Each batch of changes you save — a “commit.”"),
        Item(symbol: "arrow.triangle.pull", label: "You proposed a change", detail: "Suggesting an update to a project — a “pull request.”"),
        Item(symbol: "flag", label: "You flagged something", detail: "Reporting a bug or an idea — an “issue.”"),
        Item(symbol: "checkmark.bubble", label: "You reviewed a teammate’s work", detail: "Giving feedback on their change — a “code review.”"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What’s a contribution?")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Your rank is your GitHub contribution count — basically, how much you got done. Four kinds of work count:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.system(size: iconSize, weight: .medium))
                            .foregroundStyle(.tint)
                            .frame(width: iconWidth, height: iconHeight, alignment: .center)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.callout.weight(.semibold))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("It's the same count behind the **green squares** on your GitHub profile.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrivateContributionsTip(dismissible: false)
        }
    }
}
