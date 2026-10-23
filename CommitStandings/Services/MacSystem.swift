import AppKit

/// Platform services with no SwiftUI equivalent. All app rendering lives in SwiftUI.
@MainActor
enum MacSystem {
    static func activateAfterOpeningWindow() {
        // An accessory app must activate after the new window exists to focus it.
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    static func quit() {
        NSApplication.shared.terminate(nil)
    }

    @discardableResult
    static func copy(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}
