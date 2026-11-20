import Foundation
import WidgetKit

/// Keeps the Home Screen and Lock Screen widgets in step with the board. After each refresh (and
/// on a visibility change or Disconnect) it writes `WidgetSnapshot` to the App Group, then asks
/// WidgetKit to reload, but only when the snapshot changed: reloads come out of a daily budget.
@MainActor
final class WidgetPublisher {
    private let save: @MainActor (WidgetSnapshot?) -> Void
    private let reload: @MainActor () -> Void
    private var last: WidgetSnapshot??

    /// The defaults write to the App Group and reload through `WidgetCenter`; tests pass their own.
    init(
        save: @escaping @MainActor (WidgetSnapshot?) -> Void = WidgetPublisher.saveToAppGroup,
        reload: @escaping @MainActor () -> Void = {
            for kind in WidgetSnapshot.kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
    ) {
        self.save = save
        self.reload = reload
    }

    /// Publish a snapshot, or nil when disconnected. A repeat of the last one does nothing.
    func publish(_ snapshot: WidgetSnapshot?) {
        guard last != .some(snapshot) else { return }
        last = .some(snapshot)
        save(snapshot)
        reload()
    }

    nonisolated static func saveToAppGroup(_ snapshot: WidgetSnapshot?) {
        if let snapshot {
            try? snapshot.save()
        } else {
            WidgetSnapshot.remove()
        }
    }
}
