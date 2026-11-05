import SwiftUI

/// About Committed: how Contributions are counted (the Mac explainer's content) and the version.
struct AboutCommittedSection: View {
    var body: some View {
        Section {
            NavigationLink {
                AboutCommittedPage()
            } label: {
                Label("How Contributions are counted", systemImage: "square.grid.3x3")
            }
            LabeledContent("Version", value: Self.version)
        } header: {
            Text("About Committed")
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}

private struct AboutCommittedPage: View {
    var body: some View {
        ScrollView {
            ContributionsExplainerContent()
                .padding(20)
        }
        .navigationTitle("About Committed")
        .navigationBarTitleDisplayMode(.inline)
    }
}
