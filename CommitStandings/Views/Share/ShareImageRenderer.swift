import ImageIO
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// Renders a share card the one way every share does (the Board's widget styles, a record, a
/// Challenge): opaque, at `BoardShareFormat.renderScale`, and for the share sheet as a PNG in a
/// temporary folder of its own.
@MainActor
enum ShareImageRenderer {
    private static func renderer<Card: View>(for card: Card) -> ImageRenderer<Card> {
        let renderer = ImageRenderer(content: card)
        renderer.scale = BoardShareFormat.renderScale
        renderer.isOpaque = true
        return renderer
    }

    #if os(iOS)
    static func image(_ card: some View) -> UIImage? {
        renderer(for: card).uiImage
    }
    #endif

    static func png(_ card: some View) throws -> Data {
        guard let image = renderer(for: card).cgImage else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

    /// `card` as a PNG named `name` in the temporary folder `folder`, replacing an earlier one of
    /// the same name.
    static func file(_ card: some View, folder: String, name: String) throws -> URL {
        let data = try png(card)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
