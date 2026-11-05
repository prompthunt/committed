import SwiftUI

/// How a place moved since the start of the day (+ up, − down), drawn the same way on the board
/// rows, the iPhone summary, and Live rank. Up is green; down is muted so it never feels like a
/// scolding. Zero means no marker. Compiled into the Mac app, the iPhone app, and the Live rank
/// extension.
enum RankMovement {
    /// A chevron up or down; `doubled` draws a double chevron for two or more places.
    static func symbol(_ delta: Int, doubled: Bool = false) -> String {
        let direction = delta > 0 ? "chevron.up" : "chevron.down"
        return doubled && delta.magnitude >= 2 ? "\(direction).2" : direction
    }

    static func color(_ delta: Int) -> Color {
        delta > 0 ? .green : .secondary
    }

    /// "up 1 place today", "down 3 places today".
    static func label(_ delta: Int) -> String {
        "\(delta > 0 ? "up" : "down") \(delta.magnitude) \(delta.magnitude == 1 ? "place" : "places") today"
    }
}
