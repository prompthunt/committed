import Foundation
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Small GitHub avatars on disk in the App Group container, by login. Live rank's extension can't
/// load network images (`AsyncImage` there silently shows its placeholder), so the iPhone app saves
/// a ~90 px copy of everyone on the board after each refresh, and `AvatarView` reads it first, in
/// the app and in Live rank alike. Never part of Live rank's content state (4 KB push cap).
///
/// Mac share images use the same thumbnails from an app-local cache. Both platforms can render
/// avatars synchronously from disk after prefetching them.
struct AvatarCache: Sendable {
    /// 30 pt at 3x, Live rank's largest avatar. Live Activities render blank with large images.
    static let pixelSize = 90

    #if os(macOS)
    static let shared = AvatarCache(
        directory: URL.cachesDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.addisonk.CommitStandings", directoryHint: .isDirectory)
            .appending(path: "Avatars", directoryHint: .isDirectory)
    )
    #else
    static let appGroup = "group.com.addisonk.CommitStandings"

    /// The shared cache in the App Group container, if the entitlement makes it available.
    static let shared = AvatarCache(
        directory: FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Library/Caches/Avatars", directoryHint: .isDirectory)
    )
    #endif

    let directory: URL?

    /// The file for `login`, or nil when there's no cache or the login isn't a GitHub username
    /// (so nothing else can name a path).
    func fileURL(for login: String) -> URL? {
        guard let directory, let name = UsernameNormalization.normalize(login) else { return nil }
        return directory.appending(path: "\(name).png", directoryHint: .notDirectory)
    }

    #if os(macOS)
    func image(for login: String) -> NSImage? {
        guard let url = fileURL(for: login) else { return nil }
        return NSImage(contentsOf: url)
    }
    #else
    func image(for login: String) -> UIImage? {
        guard let url = fileURL(for: login) else { return nil }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))
    }
    #endif

    /// When `login`'s avatar was saved, or nil when it hasn't been.
    func savedDate(for login: String) -> Date? {
        guard let url = fileURL(for: login) else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Scales `imageData` down to at most `pixelSize` on its longer side and saves it as a PNG,
    /// replacing any earlier one. False when there's no cache, the login isn't a username, or the
    /// data isn't an image.
    @discardableResult
    func store(_ imageData: Data, for login: String) -> Bool {
        guard let directory, let url = fileURL(for: login),
              let png = Self.thumbnailPNG(imageData) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func thumbnailPNG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: pixelSize,
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
