#if DEBUG
import Testing
import SwiftUI
import UIKit
@testable import CommitStandingsiOS

/// Renders the Board (the `-demoBoard` data) at iPhone Duo sizes the simulator can't be put
/// into from the command line: the open inner display in landscape and portrait, a Split View
/// half, and the closed display turned sideways. Not a behavior test: it writes PNGs for the
/// design review and only runs when `DUO_RENDER_DIR` is set, e.g.
/// `TEST_RUNNER_DUO_RENDER_DIR=/tmp/renders xcodebuild test -scheme CommitStandingsiOS
///  -only-testing:CommitStandingsiOSTests/DuoLayoutRenders …`.
/// These show the Board's arrangement only. A free-standing window gets regular width from a
/// trait override, not from the device, and system bars stay anchored to the real (closed,
/// 466 pt) screen, so the tab bar is left out and bar placement and fold regions are not the
/// real device's.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DUO_RENDER_DIR"] != nil))
struct DuoLayoutRenders {

    struct Pose: CustomStringConvertible, Sendable {
        let name: String
        let size: CGSize
        let sizeClass: UserInterfaceSizeClass
        var description: String { name }
    }

    // The inner display is 2007 × 2853 px at 3x: 669 × 951 pt. Split View halves it.
    nonisolated static let poses = [
        Pose(name: "open-landscape", size: CGSize(width: 951, height: 669), sizeClass: .regular),
        Pose(name: "open-portrait", size: CGSize(width: 669, height: 951), sizeClass: .regular),
        Pose(name: "splitview-half", size: CGSize(width: 475, height: 669), sizeClass: .compact),
        // The closed outer display (466 × 678 pt) turned sideways: wide, but still compact. A
        // couple of points short, because UIKit snaps a window the screen's exact size back to it.
        Pose(name: "closed-landscape", size: CGSize(width: 676, height: 464), sizeClass: .compact),
    ]

    @Test(arguments: poses)
    func renderBoard(pose: Pose) async throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["DUO_RENDER_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        let app = AppModel(.demo())
        await app.refresh.refreshAll(reason: .manual)
        let host = UIHostingController(rootView: BoardView()
            .environment(app)
            .environment(app.store)
            .environment(app.refresh)
            .environment(app.auth)
            .environment(app.roster)
            .environment(app.notifications))
        host.traitOverrides.horizontalSizeClass = pose.sizeClass == .regular ? .regular : .compact

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: pose.size)
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        // Let layout and the arrangement settle before drawing.
        try await Task.sleep(for: .seconds(2))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: directory.appending(path: "\(pose.name)-board.png"))
    }
}
#endif
