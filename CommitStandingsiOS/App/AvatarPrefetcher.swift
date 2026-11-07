import Foundation

/// Saves avatars for the people on the board into `AvatarCache`, so Live rank can show them.
/// `AppModel` calls it after every refresh, before Live rank updates.
protocol AvatarPrefetching: Sendable {
    func prefetch(_ logins: [String]) async
}

/// Saves nothing: tests and previews.
struct NoAvatarPrefetching: AvatarPrefetching {
    func prefetch(_ logins: [String]) async {}
}

/// Fetches `github.com/<login>.png` for each login without a saved avatar from the last day, all at
/// once, and saves the small copy. A failure leaves that person on their initials until the next
/// refresh tries again.
struct GitHubAvatarPrefetcher: AvatarPrefetching {
    /// How long a saved avatar is used before it's fetched again (people do change them).
    static let maxAge: TimeInterval = 24 * 60 * 60

    let cache: AvatarCache
    var now: @Sendable () -> Date = { Date() }
    let fetch: @Sendable (URL) async throws -> Data

    static func url(for login: String) -> URL? {
        guard let name = UsernameNormalization.normalize(login) else { return nil }
        return URL(string: "https://github.com/\(name).png?size=\(AvatarCache.pixelSize)")
    }

    /// The live prefetcher: the shared App Group cache, fetched with a short timeout so a slow
    /// avatar never holds up Live rank for long.
    static func live() -> GitHubAvatarPrefetcher {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)
        return GitHubAvatarPrefetcher(cache: .shared) { url in
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
    }

    func prefetch(_ logins: [String]) async {
        let now = now()
        let due = logins.compactMap { login -> (String, URL)? in
            guard let url = Self.url(for: login) else { return nil }
            if let saved = cache.savedDate(for: login), now.timeIntervalSince(saved) < Self.maxAge { return nil }
            return (login, url)
        }
        await withTaskGroup(of: Void.self) { group in
            for (login, url) in due {
                group.addTask {
                    guard let data = try? await fetch(url) else { return }
                    cache.store(data, for: login)
                }
            }
        }
    }
}
