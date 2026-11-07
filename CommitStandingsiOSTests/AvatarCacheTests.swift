import Foundation
import Testing
import UIKit
@testable import CommitStandingsiOS

/// Small avatars on disk for Live rank, whose process can't load network images (#53): the app
/// writes them on each refresh, and the board and the Live rank extension read them by login.
struct AvatarCacheTests {
    private let cache = AvatarCache(directory: FileManager.default.temporaryDirectory
        .appending(path: "AvatarCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory))

    private func png(side: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    @Test func storesASmallPNGAndReadsItBackByLogin() throws {
        #expect(cache.store(png(side: 460), for: "alice"))

        let image = try #require(cache.image(for: "alice"))
        #expect(image.size.width * image.scale <= CGFloat(AvatarCache.pixelSize))
        #expect(image.size.height * image.scale <= CGFloat(AvatarCache.pixelSize))
        let file = try Data(contentsOf: try #require(cache.fileURL(for: "alice")))
        #expect(file.starts(with: [0x89, 0x50, 0x4e, 0x47])) // PNG
        #expect(file.count < 20_000) // Oversized images make Live Activities render blank.
    }

    @Test func aSmallImageIsNotScaledUp() throws {
        #expect(cache.store(png(side: 40), for: "bob"))

        let image = try #require(cache.image(for: "bob"))
        #expect(image.size.width * image.scale == 40)
    }

    @Test func loginsAreCaseInsensitive() {
        cache.store(png(side: 120), for: "Alice")

        #expect(cache.image(for: "alice") != nil)
        #expect(cache.fileURL(for: "ALICE") == cache.fileURL(for: "alice"))
    }

    @Test func missingAvatarIsNil() {
        #expect(cache.image(for: "nobody") == nil)
    }

    /// A login is a file name: nothing outside GitHub's alphabet can reach the file system.
    @Test(arguments: ["../escape", "a/b", "", ".", "with space", "x.png"])
    func unsafeLoginsHaveNoFile(login: String) {
        #expect(cache.fileURL(for: login) == nil)
        #expect(!cache.store(png(side: 120), for: login))
        #expect(cache.image(for: login) == nil)
    }

    @Test func undecodableDataIsNotStored() {
        #expect(!cache.store(Data("not an image".utf8), for: "carol"))
        #expect(cache.image(for: "carol") == nil)
    }

    @Test func withoutAContainerNothingIsCached() {
        let none = AvatarCache(directory: nil)

        #expect(!none.store(png(side: 120), for: "alice"))
        #expect(none.image(for: "alice") == nil)
    }

    @Test func reportsWhenEachAvatarWasSaved() throws {
        #expect(cache.savedDate(for: "dana") == nil)
        cache.store(png(side: 120), for: "dana")

        let saved = try #require(cache.savedDate(for: "dana"))
        #expect(abs(saved.timeIntervalSinceNow) < 60)
    }
}

/// Fetches avatars for everyone on the board and keeps them a day, so Live rank has a face for
/// each row without a request per refresh.
struct AvatarPrefetcherTests {
    private let cache = AvatarCache(directory: FileManager.default.temporaryDirectory
        .appending(path: "AvatarPrefetcherTests-\(UUID().uuidString)", directoryHint: .isDirectory))

    final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func append(_ url: URL) { lock.withLock { urls.append(url) } }
        var all: [URL] { lock.withLock { urls } }
    }

    private static let image: Data = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format).pngData { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 180, height: 180))
        }
    }()

    private func prefetcher(_ requests: Requests, now: Date = Date(), failing: Set<String> = []) -> GitHubAvatarPrefetcher {
        GitHubAvatarPrefetcher(cache: cache, now: { now }) { url in
            requests.append(url)
            if failing.contains(where: { url.path.contains($0) }) { throw URLError(.notConnectedToInternet) }
            return Self.image
        }
    }

    @Test func fetchesEachLoginsGitHubAvatarAtCacheSize() async {
        let requests = Requests()

        await prefetcher(requests).prefetch(["alice", "bob"])

        #expect(Set(requests.all.map(\.absoluteString)) == [
            "https://github.com/alice.png?size=90",
            "https://github.com/bob.png?size=90",
        ])
        #expect(cache.image(for: "alice") != nil)
        #expect(cache.image(for: "bob") != nil)
    }

    @Test func aFreshAvatarIsNotFetchedAgain() async {
        let requests = Requests()
        await prefetcher(requests).prefetch(["alice"])

        await prefetcher(requests, now: Date().addingTimeInterval(3_600)).prefetch(["alice"])

        #expect(requests.all.count == 1)
    }

    @Test func aDayOldAvatarIsFetchedAgain() async {
        let requests = Requests()
        await prefetcher(requests).prefetch(["alice"])

        await prefetcher(requests, now: Date().addingTimeInterval(25 * 3_600)).prefetch(["alice"])

        #expect(requests.all.count == 2)
    }

    @Test func aFailedFetchKeepsTheOthers() async {
        let requests = Requests()

        await prefetcher(requests, failing: ["bob"]).prefetch(["alice", "bob"])

        #expect(cache.image(for: "alice") != nil)
        #expect(cache.image(for: "bob") == nil)
    }

    @Test func unsafeLoginsAreNeverRequested() async {
        let requests = Requests()

        await prefetcher(requests).prefetch(["../x", "alice"])

        #expect(requests.all.map(\.absoluteString) == ["https://github.com/alice.png?size=90"])
    }
}
