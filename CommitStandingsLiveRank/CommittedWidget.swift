import SwiftUI
import WidgetKit

/// Committed on the Home Screen and the Lock Screen, and (the small size) in CarPlay and StandBy.
///
/// Every size shows Live rank's Window from `WidgetSnapshot`, which the app writes after each
/// refresh and then reloads these widgets. Between the app's refreshes the widgets refresh
/// themselves: each timeline asks for the next one 15 minutes on, and `WidgetRefresh` refetches
/// everyone's count first (iOS's reload budget may stretch that). Each size shows how long ago its
/// numbers were updated, counting up. The timeline holds the snapshot, plus one more entry at its
/// stale date (an hour after the data) that steps the colors down and turns the age amber. Without
/// a snapshot (not connected yet), the widget asks you to open Committed; the placeholder and
/// gallery use a sample board.
struct CommittedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: CommittedWidgetProvider()) { entry in
            CommittedWidgetView(entry: entry)
                .environment(\.liveRankIsStale, entry.isStale)
                // The Sample board's made-up people show initials, never a saved avatar.
                .environment(\.savedAvatars, entry.snapshot?.savedAvatars)
                .widgetURL(entry.snapshot?.state.boardURL ?? DeepLink.board(window: nil).url)
        }
        .configurationDisplayName("Committed")
        .description("Your place on the board and the people around you, updated every 15 minutes.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}

/// The board as a list in a small widget, the size StandBy shows (and, on iPhone Duo, the outer
/// screen folded into a tent): the leaders, or the first few and your race, in the board's own
/// rows. Its own widget, so the rank card stays the glanceable one for CarPlay.
struct CommittedBoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.boardListKind, provider: CommittedWidgetProvider()) { entry in
            Group {
                if let snapshot = entry.snapshot {
                    CommittedWidgetBoardSmall(snapshot: snapshot)
                } else {
                    CommittedWidgetConnect()
                }
            }
            .environment(\.liveRankIsStale, entry.isStale)
            .environment(\.savedAvatars, entry.snapshot?.savedAvatars)
            .environment(\.colorScheme, .dark)
            .containerBackground(for: .widget) { Color.ink }
            .widgetURL(entry.snapshot?.state.boardURL ?? DeepLink.board(window: nil).url)
        }
        .configurationDisplayName("Committed Board")
        .description("The board as a list: the leaders, or your race with the person ahead. Made for StandBy.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline

struct CommittedWidgetEntry: TimelineEntry {
    let date: Date
    /// nil when the app hasn't written one: not connected yet, or disconnected.
    let snapshot: WidgetSnapshot?
    let isStale: Bool

    init(date: Date, snapshot: WidgetSnapshot?) {
        self.date = date
        self.snapshot = snapshot
        isStale = snapshot.map { $0.staleDate <= date } ?? false
    }
}

struct CommittedWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CommittedWidgetEntry {
        CommittedWidgetEntry(date: .now, snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (CommittedWidgetEntry) -> Void) {
        let saved = WidgetSnapshot.load()
        // The gallery shows your own board when there is one, the sample otherwise.
        completion(CommittedWidgetEntry(date: .now, snapshot: context.isPreview ? saved ?? .sample() : saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CommittedWidgetEntry>) -> Void) {
        // WidgetKit calls this once per timeline and keeps the handler only until it's called.
        nonisolated(unsafe) let completion = completion
        Task {
            let now = Date.now
            let snapshot = await WidgetRefresh(fetcher: ContributionsClient()).current(now: now)
            var entries = [CommittedWidgetEntry(date: now, snapshot: snapshot)]
            if let snapshot, snapshot.staleDate > now {
                entries.append(CommittedWidgetEntry(date: snapshot.staleDate, snapshot: snapshot))
            }
            // The app still reloads after its own refreshes; this keeps the widgets current
            // between them.
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(WidgetRefresh.interval))))
        }
    }
}

// MARK: - Views

struct CommittedWidgetView: View {
    let entry: CommittedWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            CommittedWidgetInline(snapshot: entry.snapshot)
        case .accessoryCircular:
            CommittedWidgetCircular(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            CommittedWidgetRectangular(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        default:
            Group {
                if let snapshot = entry.snapshot {
                    switch family {
                    case .systemMedium: CommittedWidgetMedium(snapshot: snapshot)
                    case .systemLarge: CommittedWidgetLarge(snapshot: snapshot)
                    default: CommittedWidgetSmall(snapshot: snapshot)
                    }
                } else {
                    CommittedWidgetConnect()
                }
            }
            .environment(\.colorScheme, .dark)
            .containerBackground(for: .widget) { Color.ink }
        }
    }
}
