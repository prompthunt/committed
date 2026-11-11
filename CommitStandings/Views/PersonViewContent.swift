import Charts
import SwiftUI

/// How the person view is drawn. The Mac window and the iPhone sheet or pane share
/// `PersonViewContent`; the iPhone restyles it by setting `\.personViewStyle`, the way it restyles
/// `StandingRow`. The default, `.standard`, uses system fonts, the system accent for controls and
/// the brand's contribution green for the data (`Color.contributionGreen`), so it fits the Mac's
/// light and dark appearances. A nil color means the default (`.tint` for the accent, `.secondary`
/// for quiet text).
struct PersonViewStyle {
    var nameFont: Font = .title2.weight(.semibold)
    /// The race card's headline: "5 to pass odile-m".
    var raceFont: Font = .title2.weight(.bold)
    var sectionFont: Font = .headline
    var statValueFont: Font = .title3.weight(.semibold).monospacedDigit()
    var statLabelFont: Font = .caption
    var bodyFont: Font = .callout
    var captionFont: Font = .caption
    var avatarSize: CGFloat = 52
    /// Controls: the GitHub link, the "you" badge and the progress spinner. nil = `.tint`.
    var accent: Color? = nil
    /// The person's contributions: this month's bars, their race line and the race's number.
    /// nil = `Color.contributionGreen`, lime on dark and deep green on light, as on Windows.
    var dataColor: Color? = nil
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
/// the Mac window: who they are and a link to their GitHub profile; on a rival's view, their race
/// with you over the Board's 30 days (the gap, who passed whom, both running totals); their streak
/// and active days; and this month's bars over last month's in grey with a selectable bar. Before
/// their count loads it says it's waiting. Your own view adds the private-contributions tip
/// (`privateTip`, which each platform styles) and what the number can't show.
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
    private var dataColor: Color { style.dataColor ?? .contributionGreen }
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
                if let race = person.race {
                    raceCard(race)
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

    /// Two boxes side by side; stacked at accessibility text sizes.
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
        // One streak box: the longest shows in its caption only when it differs.
        stat("🔥 Streak", PersonSummary.streakValue(days.currentStreak),
             caption: PersonSummary.streakCaption(current: days.currentStreak, longest: days.longestStreak),
             spoken: "Streak",
             spokenValue: PersonSummary.streakSpoken(current: days.currentStreak, longest: days.longestStreak))
        stat("Active days", person.activeDaysText ?? "", caption: "This month", spoken: "Active days this month")
    }

    private func stat(_ label: String, _ value: String, caption: String, spoken: String? = nil,
                      spokenValue: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(style.statLabelFont)
                .foregroundStyle(secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(style.statValueFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .font(style.statLabelFont)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    // MARK: Race

    /// You against them over the Board's 30 days: the gap in the Board's words, who passed whom,
    /// and both running totals with the latest change of lead marked. Their line is drawn in the
    /// data color like their bars; yours is the quiet one.
    private func raceCard(_ race: PersonSummary.Race) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = person.raceTitle {
                Text(title)
                    .font(style.captionFont.weight(.semibold))
                    .foregroundStyle(secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let headline = person.raceHeadline {
                raceHeadline(headline)
                    .font(style.raceFont)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if let story = person.raceStory {
                Text(story)
                    .font(style.captionFont)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            raceChart(race)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.raceSpoken ?? "")
    }

    /// "5 to pass odile-m" with the 5 in the data color.
    private func raceHeadline(_ headline: String) -> Text {
        guard let number = person.raceHeadlineNumber, headline.hasPrefix(number) else { return Text(headline) }
        return Text("\(Text(number).foregroundStyle(dataColor))\(String(headline.dropFirst(number.count)))")
    }

    private func raceChart(_ race: PersonSummary.Race) -> some View {
        let days = max(race.yours.count, race.theirs.count)
        let level = race.leader == nil
        let marked = race.story.day.flatMap { day -> (day: Int, total: Int, side: PersonSummary.Side)? in
            guard let side = race.story.side else { return nil }
            let line = side == .you ? race.yours : race.theirs
            return line.indices.contains(day - 1) ? (day, line[day - 1], side) : nil
        }
        return Chart {
            ForEach(Array(race.yours.enumerated()), id: \.offset) { index, total in
                LineMark(x: .value("Day", index + 1), y: .value("Running total", total),
                         series: .value("Who", "you"))
                    .foregroundStyle(secondaryColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(race.theirs.enumerated()), id: \.offset) { index, total in
                LineMark(x: .value("Day", index + 1), y: .value("Running total", total),
                         series: .value("Who", "them"))
                    .foregroundStyle(dataColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if let marked {
                PointMark(x: .value("Day", marked.day), y: .value("Running total", marked.total))
                    .foregroundStyle(marked.side == .you ? secondaryColor : dataColor)
                    .symbolSize(48)
            }
            // Each line's total at its end, the higher one above the lower so they never collide.
            if level {
                PointMark(x: .value("Day", days), y: .value("Running total", race.theirTotal))
                    .opacity(0)
                    .annotation(position: .trailing, spacing: 6) {
                        endLabel("\(race.theirTotal.formatted()) each", color: style.secondaryColor)
                    }
            } else {
                let theyLead = race.leader == .them
                PointMark(x: .value("Day", days), y: .value("Running total", race.theirTotal))
                    .opacity(0)
                    .annotation(position: theyLead ? .topTrailing : .bottomTrailing, spacing: 2) {
                        endLabel("\(race.theirTotal.formatted()) \(person.login)", color: dataColor)
                    }
                PointMark(x: .value("Day", days), y: .value("Running total", race.yourTotal))
                    .opacity(0)
                    .annotation(position: theyLead ? .bottomTrailing : .topTrailing, spacing: 2) {
                        endLabel("\(race.yourTotal.formatted()) you", color: style.secondaryColor)
                    }
            }
        }
        .chartXScale(domain: 1...max(2, days), range: .plotDimension(endPadding: 88))
        // Headroom above the leader so the top label stays inside the chart, clear of the story.
        .chartYScale(domain: 0...(Double(max(1, race.theirTotal, race.yourTotal)) * 1.3))
        .chartXAxis {
            AxisMarks(values: [1, days]) { value in
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text(day == days ? "Today" : race.dates.first ?? "")
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 96)
    }

    private var secondaryColor: Color { style.secondaryColor ?? .secondary }

    private func endLabel(_ text: String, color: Color?) -> some View {
        Text(text)
            .font(style.captionFont.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .lineLimit(1)
            .fixedSize()
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
            legendItem(dataColor, person.month.name, days.thisMonth.reduce(0, +))
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
                    .foregroundStyle(day == selected ? dataColor : dataColor.opacity(0.55))
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

extension Color {
    /// Contributions in the brand's green on the Mac and in the shared person view's default style:
    /// lime (#c8ff2e) on dark, deep green (#476510) on light, where lime can't be read. The same
    /// pair as the Windows app's `--bar`.
    static let contributionGreen: Color = {
        let lime = (red: 200.0 / 255, green: 1.0, blue: 46.0 / 255)
        let deep = (red: 71.0 / 255, green: 101.0 / 255, blue: 16.0 / 255)
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? lime : deep
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? lime : deep
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #endif
    }()
}
