import SwiftUI

struct EmptyStateView: View {
    @Environment(RefreshCoordinator.self) private var refresh
    var body: some View {
        VStack(spacing: 10) {
            Text("Your GitHub circle").font(.headline)
            Text("We’ll load you, your organization members, and the people you follow.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Load people") { Task { await refresh.refreshAll(reason: .manual) } }
                .disabled(refresh.isRefreshing)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
    }
}
