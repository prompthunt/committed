import SwiftUI

/// The Mac's private-contributions tip (`PrivateContributionsTip`, same copy and dismissal) in the
/// iPhone's materials: a tile card, a soft icon, and a tile button rather than a lime one.
struct PrivateWorkTip: View {
    @AppStorage("dismissedPrivateContribTip") private var dismissed = false
    /// Your own person view shows it always, like the Mac's About Committed.
    var dismissible = true

    var body: some View {
        if !dismissible || !dismissed {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open").foregroundStyle(Color.soft)
                    Text("Want your private work to count?")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    if dismissible {
                        Button {
                            dismissed = true
                        } label: {
                            Image(systemName: "xmark").imageScale(.small).foregroundStyle(Color.muted)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss tip")
                    }
                }
                .padding(.bottom, dismissible ? -10 : 0)
                Text("Include private repo and org activity: on your GitHub profile, above the green squares, choose **Contribution settings → Private contributions**.")
                    .font(.footnote)
                    .foregroundStyle(Color.soft)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Only daily counts are shared. Your code and repo details stay private.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: URL(string: "https://docs.github.com/en/account-and-profile/how-tos/contribution-settings/manage-visibility-settings-for-private-contributions-and-achievements")!) {
                    Label("How to enable on GitHub", systemImage: "arrow.up.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(TileButtonStyle())
                .padding(.top, 4)
            }
            .padding(16)
            .tileCard()
        }
    }
}
