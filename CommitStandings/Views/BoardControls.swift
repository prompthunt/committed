import SwiftUI

/// Gentle "update available" banner shown above the board when Sparkle has found a
/// scheduled update. `Update` activates the app and hands off to Sparkle's install prompt;
/// the ✕ dismisses this version until a newer one appears (the menu-bar dot persists).
struct UpdateBanner: View {
    let version: String
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Update to \(version)")
                    .font(.caption.weight(.semibold))
                Text("A new version is ready to install")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button("Update", action: onUpdate)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss until the next version")
            .accessibilityLabel("Dismiss update notice")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.tint.opacity(0.4), lineWidth: 1)
        )
    }
}

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
