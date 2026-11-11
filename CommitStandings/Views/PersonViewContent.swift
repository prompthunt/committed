import Charts
import SwiftUI

/// How the person view is drawn. The Mac window and the iPhone sheet or pane share
/// `PersonViewContent`; the iPhone restyles it by setting `\.personViewStyle`, the way it restyles
/// `StandingRow`. The default, `.standard`, uses system colors and fonts only, so it fits the
/// Mac's light and dark appearances. A nil color means the system's (`.tint` for the accent,
/// `.secondary` for quiet text).
struct PersonViewStyle {
    var nameFont: Font = .title2.weight(.semibold)
    var sectionFont: Font = .headline
    var statValueFont: Font = .title3.weight(.semibold).monospacedDigit()
    var statLabelFont: Font = .caption
    var bodyFont: Font = .callout
    var captionFont: Font = .caption
    var avatarSize: CGFloat = 52
    /// This month's bars, the "you" badge and the selected bar. nil = `.tint`.
    var accent: Color? = nil
    /// The "you" badge's label. nil = the accent.
    var badgeForeground: Color? = nil
    /// Last month's bars behind this month's.
    var pastBarColor: Color = .gray.opacity(0.35)
    /// Quiet text. nil = `.secondary`.
    var secondaryColor: Color? = nil
    /// The stat boxes' and waiting card's background. nil = the system's quaternary fill.
    var cardColor: Color? = nil
    var cornerRadius: CGFloat = 12

    static let standard = PersonViewStyle()
}

extension EnvironmentValues {
    @Entry var personViewStyle = PersonViewStyle.standard
}

/// A Competitor's person view, shared by the iPhone (sheet, or the second pane on iPhone Duo) and
/// the Mac window: who they are and a link to their GitHub profile, then their current and
/// longest streaks and active days, and this month's bars over last month's in grey with a
/// selectable bar. Before their count loads it says it's waiting. Your own view adds the private-contributions tip (`privateTip`, which each platform
/// styles) and what the number can't show.
///
/// The host scrolls it and sets its width; this view has no platform-only types.
struct PersonViewContent<Tip: View>: View {
    let person: PersonSummary
    private let privateTip: Tip
    @Environment(\.personViewStyle) private var style
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The selected bar's day of the month: today until another is picked.
    @State private var selectedDay: Int
    @State private var touchedBar: String?

    init(person: PersonSummary, initialDay: Int? = nil, @ViewBuilder privateTip: () -> Tip) {
        self.person = person
        self.privateTip = privateTip()
        _selectedDay = State(initialValue: initialDay ?? person.dayOfMonth)
    }

    private var accent: Color { style.accent ?? .accentColor }
    private var secondary: AnyShapeStyle {
        style.secondaryColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if let days = person.days {
                if person.status == .failed {
                    Text("Refresh failed · showing saved counts")
                        .font(style.captionFont)
                        .foregroundStyle(secondary)
                }
                stats(days)
                month(days)
            } else {
                waiting
            }
            if person.isYou {
                privateTip
                ContributionLimitsNote()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(username: person.login, size: style.avatarSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(person.login)
                    .font(style.nameFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if person.isYou {
                    Text("you")
                        .font(style.captionFont.weight(.bold))
                        .foregroundStyle(style.badgeForeground ?? accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(accent.opacity(style.badgeForeground == nil ? 0.18 : 1), in: Capsule())
                        .accessibilityLabel("This is you")
                }
            }
            Spacer(minLength: 8)
            Link(destination: person.profileURL) {
                Label("GitHub", systemImage: "arrow.up.right")
                    .font(style.bodyFont.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize()
            }
            .tint(accent)
            .accessibilityLabel("GitHub profile")
            .accessibilityHint("Opens \(person.login) on GitHub")
        }
    }

    // MARK: Stats

    /// Three boxes side by side; stacked at accessibility text sizes.
    @ViewBuilder
    private func stats(_ days: PersonSummary.Days) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) { statBoxes(days) }
        } else {
            HStack(alignment: .top, spacing: 8) { statBoxes(days) }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func statBoxes(_ days: PersonSummary.Days) -> some View {
        stat("🔥 Current streak", PersonSummary.streakText(days.currentStreak), spoken: "Current streak",
             spokenValue: StreakLabel.spokenDays(days.currentStreak))
        stat("Longest streak", PersonSummary.streakText(days.longestStreak),
             spokenValue: StreakLabel.spokenDays(days.longestStreak))
        stat("Active days", person.activeDaysText ?? "", spoken: "Active days this month")
    }

    private func stat(_ label: String, _ value: String, spoken: String? = nil, spokenValue: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(style.statLabelFont)
                .foregroundStyle(secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(value)
                .font(style.statValueFont)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? label)
        .accessibilityValue(spokenValue ?? value)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .fill(style.cardColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.quaternary.opacity(0.5)))
    }

    // MARK: Month

    private func month(_ days: PersonSummary.Days) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(person.month.name)
                    .font(style.sectionFont)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                legend(days)
            }
            let day = min(max(1, selectedDay), max(1, days.thisMonth.count))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { selectedCaption(day) }
                VStack(alignment: .leading, spacing: 2) { selectedCaption(day) }
            }
            .accessibilityElement(children: .combine)
            chart(days, selected: day)
        }
    }

    private func legend(_ days: PersonSummary.Days) -> some View {
        HStack(spacing: 10) {
            legendItem(accent, person.month.name, days.thisMonth.reduce(0, +))
            legendItem(style.pastBarColor, person.lastMonth.name, days.lastMonth.reduce(0, +))
        }
        .font(style.captionFont)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ color: Color, _ name: String, _ total: Int) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(name).foregroundStyle(secondary)
            Text(total.formatted()).fontWeight(.semibold).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(PersonSummary.plural(total, "contribution"))")
    }

    @ViewBuilder
    private func selectedCaption(_ day: Int) -> some View {
        if let text = person.selectedDayText(day) {
            Text(text).font(style.bodyFont.weight(.semibold)).monospacedDigit()
        }
        if let comparison = person.selectedDayComparison(day) {
            Text(comparison).font(style.bodyFont).monospacedDigit().foregroundStyle(secondary)
        }
    }

    private func chart(_ days: PersonSummary.Days, selected: Int) -> some View {
        let slots = max(person.daysInMonth, days.lastMonth.count)
        return Chart {
            ForEach(Array(days.lastMonth.enumerated()), id: \.offset) { index, count in
                BarMark(x: .value("Day", String(index + 1)), y: .value("Contributions", count),
                        width: .ratio(0.86), stacking: .unstacked)
                    .foregroundStyle(style.pastBarColor)
                    .cornerRadius(2)
                    .accessibilityHidden(true)
            }
            ForEach(Array(days.thisMonth.enumerated()), id: \.offset) { index, count in
                let day = index + 1
                let bar = person.bar(day: day)
                BarMark(x: .value("Day", String(day)), y: .value("Contributions", count),
                        width: .ratio(0.5), stacking: .unstacked)
                    .foregroundStyle(day == selected ? accent : accent.opacity(0.55))
                    .cornerRadius(2)
                    .accessibilityLabel(bar?.label ?? "")
                    .accessibilityValue(bar?.value ?? "")
            }
        }
        .chartXScale(domain: (1...slots).map(String.init))
        .chartXAxis {
            // Weekly ticks only (1, 8, 15, 22, 29): thirty-one labels don't fit.
            AxisMarks { value in
                if let day = value.as(String.self).flatMap(Int.init), day % 7 == 1 {
                    AxisValueLabel()
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $touchedBar)
        .onChange(of: touchedBar) {
            if let touchedBar, let day = Int(touchedBar), days.thisMonth.indices.contains(day - 1) {
                selectedDay = day
            }
        }
        .frame(height: 160)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(person.chartSummary ?? "")
    }

    // MARK: Waiting

    private var waiting: some View {
        HStack(alignment: .top, spacing: 12) {
            if person.status == .loading {
                ProgressView().tint(accent)
            } else {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .foregroundStyle(secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(person.waitingTitle)
                    .font(style.bodyFont.weight(.semibold))
                Text(person.waitingDetail)
                    .font(style.captionFont)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(card)
        .accessibilityElement(children: .combine)
    }
}

extension PersonViewContent where Tip == PrivateContributionsTip {
    /// The person view with the Mac's private-contributions tip, always shown on your own view.
    init(person: PersonSummary, initialDay: Int? = nil) {
        self.init(person: person, initialDay: initialDay) {
            PrivateContributionsTip(dismissible: false)
        }
    }
}

/// What the Contributions count can't show (#89), under your own person view: it counts activity,
/// not quality, and leaves out private work unless its owner shares it.
struct ContributionLimitsNote: View {
    @Environment(\.personViewStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What this number can’t show")
                .font(style.bodyFont.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Contributions count activity, not how good or hard the work was. Automated commits and bots count like anyone’s, and private work counts only when its owner turns on private contributions.")
                .font(style.captionFont)
                .foregroundStyle(style.secondaryColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
