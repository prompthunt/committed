import Foundation

/// Pure decision logic for the "update available" prompt, kept out of the view body so it
/// can be unit-tested without a live Sparkle session. The menu-bar dot keys off
/// `updateAvailable` directly; only the in-popover banner is gated by per-version dismissal.
enum UpdatePromptState {
    /// The banner shows when an update is available, carries a version, and that exact
    /// version hasn't been dismissed. A newer version differs from the dismissed string, so
    /// dismissing 0.1.8 does not suppress the banner for a later 0.1.9.
    static func shouldShowBanner(
        updateAvailable: Bool,
        latestVersion: String?,
        dismissedVersion: String?
    ) -> Bool {
        guard updateAvailable, let latestVersion, !latestVersion.isEmpty else { return false }
        return latestVersion != normalized(dismissedVersion)
    }

    /// Treats an empty stored string (the `@AppStorage` default) as "nothing dismissed".
    static func normalized(_ dismissedVersion: String?) -> String? {
        guard let dismissedVersion, !dismissedVersion.isEmpty else { return nil }
        return dismissedVersion
    }
}
