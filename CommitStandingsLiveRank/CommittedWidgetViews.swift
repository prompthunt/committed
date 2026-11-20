import SwiftUI

/// Not connected: what to do, in place of a board.
struct CommittedWidgetConnect: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrophyMark(size: 22)
            Spacer(minLength: 0)
            Text("Open Committed and connect GitHub to see your rank.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

enum CommittedWidgetText {
    /// "#3 · 42 today", or "42 today" without a rank, or the Window alone without a count.
    static func headline(_ state: LiveRankState) -> String {
        let window = state.contributionWindow?.shortTitle.lowercased() ?? ""
        let count = state.contributions.map { "\($0) \(window)" }
        switch (state.rank, count) {
        case let (rank?, count?): return "#\(rank) · \(count)"
        case let (nil, count?): return count
        default: return state.contributionWindow?.shortTitle ?? "Committed"
        }
    }
}

// MARK: - Lock Screen

/// "#3 · 42 today" over how long ago it was updated ("13 min, 36 sec", counting up). Rendered in
/// the Lock Screen's tint, so no color carries meaning.
struct CommittedWidgetRectangular: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let state = snapshot?.state {
                Text(CommittedWidgetText.headline(state))
                    .font(.headline)
                    .widgetAccentable()
                if state.contributions == nil || state.competitorCount <= 1, let line = state.emptyStateLine {
                    Text(line).font(.caption)
                } else {
                    Label { Text(state.updatedDate, style: .relative).monospacedDigit() } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Updated \(Text(state.updatedDate, style: .relative)) ago"))
                }
            } else {
                Text("Committed").font(.headline).widgetAccentable()
                Text("Connect GitHub to see your rank").font(.caption)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line above the clock: your rank and count.
struct CommittedWidgetInline: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let state = snapshot?.state {
            Label(CommittedWidgetText.headline(state), systemImage: "trophy.fill")
        } else {
            Label("Committed", systemImage: "trophy.fill")
        }
    }
}

/// The trophy over your rank.
struct CommittedWidgetCircular: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "trophy.fill")
                .font(.caption)
                .widgetAccentable()
            Text(snapshot?.state.rank.map { "#\($0)" } ?? "–")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.map { LiveRankText.rankAccessibility($0.state) } ?? "Committed")
    }
}
