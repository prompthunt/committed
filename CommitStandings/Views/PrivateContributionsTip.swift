import SwiftUI

/// Shared setup reminder for onboarding and the board. The explainer keeps it available
/// after dismissal. We read the public graph and cannot detect this setting per user.
struct PrivateContributionsTip: View {
    @AppStorage("dismissedPrivateContribTip") private var dismissed = false
    var dismissible = true

    var body: some View {
        if !dismissible || !dismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open")
                        .foregroundStyle(.tint)
                    Text("Want your private work to count?")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    if dismissible {
                        Button {
                            dismissed = true
                        } label: {
                            Image(systemName: "xmark").imageScale(.small).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss tip")
                    }
                }
                Text("Include private repo and org activity: on your GitHub profile, above the green squares, choose **Contribution settings → Private contributions**.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Only daily counts are shared. Your code and repo details stay private.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("How to enable on GitHub", destination: URL(string: "https://docs.github.com/en/account-and-profile/how-tos/contribution-settings/manage-visibility-settings-for-private-contributions-and-achievements")!)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(11)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.tint.opacity(0.35), lineWidth: 1)
            )
        }
    }
}
