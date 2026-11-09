import SwiftUI
import WidgetKit

/// Committed on the Home Screen and the Lock Screen, and (the small size) in CarPlay and StandBy.
///
/// Every size shows Live rank's Window from `WidgetSnapshot`, which the app writes after each
/// refresh and then reloads these widgets. Nothing is fetched here. The timeline holds the snapshot
/// as written, plus one more entry at its stale date (20 minutes after the data) that steps the
/// colors down and adds the clock, as Live rank does. Without a snapshot (not connected yet), the
/// widget asks you to open Committed; the placeholder and gallery use a sample board.
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
        .description("Your place on the board, and how many Contributions to pass the person ahead.")
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
        isStale = snapshot.map { $0.state.staleDate <= date } ?? false
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
        let now = Date.now
        let saved = WidgetSnapshot.load()
        var entries = [CommittedWidgetEntry(date: now, snapshot: saved)]
        if let saved, saved.state.staleDate > now {
            entries.append(CommittedWidgetEntry(date: saved.state.staleDate, snapshot: saved))
        }
        // The app reloads after every refresh; there's nothing to fetch from here.
        completion(Timeline(entries: entries, policy: .never))
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
