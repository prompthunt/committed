import Foundation

/// Static GitHub OAuth configuration. The Device Flow client ID is a *public*
/// identifier (no secret), safe to embed in the distributed app.
enum GitHubConfig {
    /// OAuth app client ID (Device Flow enabled). Register at
    /// https://github.com/settings/developers.
    static let clientID = "Ov23lij4oZbEeMZk3889"

    /// Scopes requested at sign-in. `read:org`/`read:user` power org + follow suggestions only.
    /// We deliberately do NOT request `repo` — that would grant read+write to all private repos
    /// (a scary consent screen for a leaderboard). The contributions metric is scraped
    /// anonymously regardless of scope. See PRODUCT.md for the privacy model.
    static let scope = "read:org read:user"
}
