import ImageIO
import SwiftUI
import Testing
@testable import CommitStandings

@MainActor
struct BoardShareRenderTests {
    @Test(arguments: BoardShareStyle.allCases, BoardShareFormat.allCases)
    func macExportsPNGAtTheSelectedSize(style: BoardShareStyle, format: BoardShareFormat) throws {
        let snapshot = WidgetSnapshot.sample()
        let file = try BoardShareRenderer.file(snapshot, style: style, format: format)
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(file.lastPathComponent == "Committed-Today-\(style.rawValue)-\(format.rawValue).png")
        #expect(CGSize(width: image.width, height: image.height) == format.pixelSize)
    }
}
