import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
#if os(macOS)
@testable import CommitStandings
#else
@testable import CommitStandingsiOS
#endif

@MainActor
struct BoardShareRenderTests {
    #if os(macOS)
    @Test(arguments: BoardShareStyle.allCases, BoardShareFormat.allCases)
    func macExportsPNGAtTheSelectedSize(style: BoardShareStyle, format: BoardShareFormat) throws {
        let snapshot = WidgetSnapshot.sample()
        let file = try BoardShareRenderer.file(snapshot, style: style, format: format, avatarCache: nil)
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(file.lastPathComponent == "Committed-Today-\(style.rawValue)-\(format.rawValue).png")
        #expect(CGSize(width: image.width, height: image.height) == format.pixelSize)
    }
    #endif

    @Test func boardStoryUsesCachedAvatars() throws {
        // One snapshot and one set of avatars for both platforms' share image evidence.
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AvatarCache(directory: directory)
        let snapshot = WidgetSnapshot.sample(now: Date(timeIntervalSince1970: 1_794_172_920))
        for (index, row) in snapshot.top.enumerated() {
            #expect(cache.store(try fixtureAvatar(index), for: row.login))
        }

        let withoutAvatars = try ShareImageRenderer.png(BoardShareCard(snapshot: snapshot, style: .board,
                                                                       format: .story, avatarCache: nil))
        let file = try BoardShareRenderer.file(snapshot, style: .board, format: .story, avatarCache: cache)
        let png = try Data(contentsOf: file)
        #expect(png != withoutAvatars)

        if let output = ProcessInfo.processInfo.environment["RENDER_DIR"] {
            #if os(macOS)
            let platform = "mac"
            #else
            let platform = "iphone"
            #endif
            let folder = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("\(platform)-matching-board-story.png"))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil),
          arguments: ContributionWindow.allCases, BoardShareFormat.allCases)
    func rankExportsForComparison(window: ContributionWindow, format: BoardShareFormat) throws {
        let output = try #require(ProcessInfo.processInfo.environment["RENDER_DIR"])
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var snapshot = WidgetSnapshot.sample(now: Date(timeIntervalSince1970: 1_794_172_920))
        let count = switch window {
        case .daily: 260
        case .weekly: 1_240
        case .monthly: 4_620
        }
        snapshot.state = LiveRankState(window: window.rawValue, rank: 6, competitorCount: 27,
                                       contributions: count, above: nil, below: nil,
                                       movementToday: 0, streak: 14, updatedAt: 1_794_172_920)
        let avatarDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: avatarDirectory) }
        let cache = AvatarCache(directory: avatarDirectory)
        #expect(cache.store(try fixtureAvatar(0), for: snapshot.selfLogin))
        let fallback = try ShareImageRenderer.png(BoardShareCard(snapshot: snapshot, style: .rank,
                                                                 format: format, avatarCache: nil))
        let png = try ShareImageRenderer.png(BoardShareCard(snapshot: snapshot, style: .rank,
                                                            format: format, avatarCache: cache))
        #expect(png != fallback)
        #if os(macOS)
        let platform = "mac"
        #else
        let platform = "iphone"
        #endif
        try png.write(to: folder.appendingPathComponent("\(platform)-rank-\(window.rawValue)-\(format.rawValue).png"))
    }

    private func fixtureAvatar(_ index: Int) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 90, height: 90, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let colors: [UInt32] = [0xa14acd, 0x248da5, 0xd45779, 0x615cd6, 0xdd7935, 0x389b50]
        let color = Palette.RGB(colors[index % colors.count])
        context.setFillColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 90, height: 90))
        context.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: 1)
        for row in 0..<5 {
            for column in 0..<5 where (row * 5 + min(column, 4 - column) * 3 + index * 2) % 7 < 4 {
                context.fill(CGRect(x: 10 + column * 14, y: 10 + row * 14, width: 14, height: 14))
            }
        }
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
