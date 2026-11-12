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
    /// The GitHub link in the header. The iPhone turns it off and puts the link in its bar, so the
    /// header's only bright color is the person's data.
    var showsProfileLink = true

    static let standard = PersonViewStyle()
}

/// Which parts of the person view to draw. One column draws `.all`; a host with room for two puts
/// `.overview` (who they are, the race, the stats and your notes) beside `.month`.
enum PersonViewPart: Sendable {
    case all, overview, month

    var overview: Bool { self != .month }
    var month: Bool { self != .overview }
}

extension EnvironmentValues {
    @Entry var personViewStyle = PersonViewStyle.standard
}

/// A Competitor's person view, shared by the iPhone (sheet, or the second pane on iPhone Duo) and
/// the Mac window: who they are and a link to their GitHub profile; on a rival's view, their race
/// with you over the Board's 30 days (the gap, who passed whom, and the lead day by day); their
/// streak and active days; and this month's bars over last month's in grey, with the selected day
/// called out on the chart. Before
/// their count loads it says it's waiting. Your own view adds the private-contributions tip
/// (`privateTip`, which each platform styles) and what the number can't show.
///
/// The host scrolls it and sets its width; this view has no platform-only types.
struct PersonViewContent<Tip: View>: View {
    let person: PersonSummary
    private let part: PersonViewPart
    private let privateTip: Tip
    @Environment(\.personViewStyle) private var style
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The selected bar's day of the month: today until another is picked.
    @State private var selectedDay: Int
    @State private var touchedBar: String?

    init(person: PersonSummary, initialDay: Int? = nil, part: PersonViewPart = .all,
         @ViewBuilder privateTip: () -> Tip) {
        self.person = person
        self.part = part
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
            if part.overview {
                header
            }
            if let days = person.days {
                if part.overview {
                    if person.status == .failed {
                        Text("Refresh failed · showing saved counts")
                            .font(style.captionFont)
                            .foregroundStyle(secondary)
                    }
                    if let race = person.race {
                        raceCard(race)
                    }
                    stats(days)
                }
                if part.month {
                    month(days)
                }
            } else if part.overview {
                waiting
            }
            if person.isYou, part.overview {
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
            if style.showsProfileLink {
                profileLink
            }
        }
    }

    private var profileLink: some View {
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
        stat("Streak", PersonSummary.streakValue(days.currentStreak), marked: true,
             caption: PersonSummary.streakCaption(current: days.currentStreak, longest: days.longestStreak),
             spoken: "Streak",
             spokenValue: PersonSummary.streakSpoken(current: days.currentStreak, longest: days.longestStreak))
        stat("Active days", person.activeDaysText ?? "", caption: "This month", spoken: "Active days this month")
    }

    /// `marked` puts the streak mark before the label, as the rows show a streak.
    private func stat(_ label: String, _ value: String, marked: Bool = false, caption: String, spoken: String? = nil,
                      spokenValue: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if marked {
                    StreakMark(size: 11, relativeTo: .caption, color: style.accent)
                }
                Text(label)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(style.statLabelFont)
            .foregroundStyle(secondary)
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
    /// and the lead day by day with the latest change of lead marked. Their side is shaded in the
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

    /// The race as the lead between you: above the even line you're ahead, below it they are,
    /// shaded in the leader's color, so the gap the headline names is the distance from the line.
    /// The latest change of lead is marked, and the end says by how much and for whom.
    private func raceChart(_ race: PersonSummary.Race) -> some View {
        let points = RacePoint.leads(race)
        let days = max(points.count, 1)
        // Fit the lead, but keep a band on each side of even so both labels have room and ahead
        // always reads up.
        let reach = Double(max(points.map { abs($0.lead) }.max() ?? 0, 1))
        let top = max(Double(points.map(\.lead).max() ?? 0), reach * 0.3) * 1.2
        let bottom = min(Double(points.map(\.lead).min() ?? 0), -reach * 0.3) * 1.2
        let marked = race.story.day.flatMap { day in points.first { $0.day == day } }
        let last = points.last
        return Chart {
            RuleMark(y: .value("Lead", 0))
                .foregroundStyle(secondaryColor.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(points) { point in
                AreaMark(x: .value("Day", point.day), yStart: .value("Lead", 0),
                         yEnd: .value("Lead", max(point.lead, 0)), series: .value("Ahead", "you"))
                    .foregroundStyle(secondaryColor.opacity(0.3))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                AreaMark(x: .value("Day", point.day), yStart: .value("Lead", 0),
                         yEnd: .value("Lead", min(point.lead, 0)), series: .value("Ahead", "them"))
                    .foregroundStyle(dataColor.opacity(0.3))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                LineMark(x: .value("Day", point.day), y: .value("Lead", point.lead),
                         series: .value("Ahead", "lead"))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            // Which side is which, quietly, at the start of each half.
            PointMark(x: .value("Day", 1), y: .value("Lead", top))
                .opacity(0)
                .annotation(position: .bottomTrailing, alignment: .leading, spacing: 0) {
                    bandLabel("You ahead")
                }
            PointMark(x: .value("Day", 1), y: .value("Lead", bottom))
                .opacity(0)
                .annotation(position: .topTrailing, alignment: .leading, spacing: 0) {
                    bandLabel("\(person.login) ahead")
                }
            if let marked, let side = race.story.side {
                PointMark(x: .value("Day", marked.day), y: .value("Lead", marked.lead))
                    .foregroundStyle(side == .you ? secondaryColor : dataColor)
                    .symbolSize(44)
            }
            if let last {
                PointMark(x: .value("Day", last.day), y: .value("Lead", last.lead))
                    .foregroundStyle(endColor(race.leader))
                    .symbolSize(30)
                    .annotation(position: .trailing, spacing: 6) {
                        endLabel(endText(race), color: race.leader == .them ? dataColor : style.secondaryColor)
                    }
            }
        }
        .chartXScale(domain: 1...max(2, days), range: .plotDimension(endPadding: 76))
        .chartYScale(domain: bottom...top)
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
        .frame(height: 120)
    }

    /// "+27 odile-m", "+12 you" or "Level".
    private func endText(_ race: PersonSummary.Race) -> String {
        switch race.leader {
        case .them: "+\(race.gap.formatted()) \(person.login)"
        case .you: "+\(race.gap.formatted()) you"
        case nil: "Level"
        }
    }

    private func endColor(_ leader: PersonSummary.Side?) -> Color {
        leader == .them ? dataColor : secondaryColor
    }

    private func bandLabel(_ text: String) -> some View {
        Text(text)
            .font(style.captionFont)
            .foregroundStyle(secondary)
            .lineLimit(1)
            .fixedSize()
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

    /// This month's name and total (in the bars' color, so it doubles as their key), last month's
    /// beside it, and the bars with the selected day called out on the chart itself.
    private func month(_ days: PersonSummary.Days) -> some View {
        let day = min(max(1, selectedDay), max(1, days.thisMonth.count))
        return VStack(alignment: .leading, spacing: 10) {
            monthHeader(days)
            chart(days, selected: day)
        }
    }

    private func monthHeader(_ days: PersonSummary.Days) -> some View {
        let total = days.thisMonth.reduce(0, +)
        let pastTotal = days.lastMonth.reduce(0, +)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                monthTitle(total)
                Spacer(minLength: 8)
                pastLegend(pastTotal)
            }
            VStack(alignment: .leading, spacing: 4) {
                monthTitle(total)
                pastLegend(pastTotal)
            }
        }
    }

    private func monthTitle(_ total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(person.month.name)
            Text(total.formatted())
                .foregroundStyle(dataColor)
                .monospacedDigit()
        }
        .font(style.sectionFont)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.month.name), \(PersonSummary.plural(total, "contribution"))")
        .accessibilityAddTraits(.isHeader)
    }

    private func pastLegend(_ total: Int) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(style.pastBarColor).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(person.lastMonth.name).foregroundStyle(secondary)
            Text(total.formatted()).fontWeight(.semibold).monospacedDigit()
        }
        .font(style.captionFont)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.lastMonth.name), \(PersonSummary.plural(total, "contribution"))")
    }

    /// The selected day's callout above its bar: this month's count, then last month's same day.
    private func callout(_ day: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let text = person.selectedDayText(day) {
                Text(text).font(style.captionFont.weight(.semibold))
            }
            if let comparison = person.selectedDayComparison(day) {
                Text(comparison).font(style.captionFont).foregroundStyle(secondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(card)
    }

    private func chart(_ days: PersonSummary.Days, selected: Int) -> some View {
        let slots = max(person.daysInMonth, days.lastMonth.count)
        let elapsed = days.thisMonth.count
        let peak = Double(max(days.thisMonth.max() ?? 0, days.lastMonth.max() ?? 0, 1))
        return Chart {
            ForEach(DayBar.bars(days.lastMonth)) { bar in
                // Days still to come this month fade, so last month reads as the comparison and not
                // as this month's data.
                BarMark(x: .value("Day", String(bar.day)), y: .value("Contributions", bar.count),
                        width: .ratio(0.86), stacking: .unstacked)
                    .foregroundStyle(style.pastBarColor.opacity(bar.day > elapsed ? 0.45 : 1))
                    .cornerRadius(2)
                    .accessibilityHidden(true)
            }
            ForEach(DayBar.bars(days.thisMonth)) { bar in
                let label = person.bar(day: bar.day)
                BarMark(x: .value("Day", String(bar.day)), y: .value("Contributions", bar.count),
                        width: .ratio(0.5), stacking: .unstacked)
                    .foregroundStyle(bar.day == selected ? dataColor : dataColor.opacity(0.55))
                    .cornerRadius(2)
                    .accessibilityLabel(label?.label ?? "")
                    .accessibilityValue(label?.value ?? "")
            }
            // The selection, drawn where it is: a rule up from the bar to its callout.
            RuleMark(x: .value("Day", String(selected)), yStart: .value("Contributions", 0),
                     yEnd: .value("Contributions", peak * 1.12))
                .foregroundStyle(secondaryColor.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .accessibilityHidden(true)
                .annotation(position: .top, spacing: 2,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    callout(selected)
                }
        }
        .chartXScale(domain: (1...slots).map(String.init))
        // Headroom above the tallest bar for the callout.
        .chartYScale(domain: 0...(peak * 1.7))
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
        .frame(height: part == .month ? 260 : 190)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(person.chartSummary ?? "")
        .accessibilityValue([person.selectedDayText(selected), person.selectedDayComparison(selected)]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Drag across the bars to pick a day")
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

/// One raced day: your running total minus theirs, so above zero you lead.
private struct RacePoint: Identifiable {
    let day: Int
    let lead: Int
    var id: Int { day }

    static func leads(_ race: PersonSummary.Race) -> [RacePoint] {
        zip(race.yours, race.theirs).enumerated().map { RacePoint(day: $0.offset + 1, lead: $0.element.0 - $0.element.1) }
    }
}

/// One day's count in the month chart, identified by its day.
private struct DayBar: Identifiable {
    let day: Int
    let count: Int
    var id: Int { day }

    static func bars(_ counts: [Int]) -> [DayBar] {
        counts.enumerated().map { DayBar(day: $0.offset + 1, count: $0.element) }
    }
}

extension PersonViewContent where Tip == PrivateContributionsTip {
    /// The person view with the Mac's private-contributions tip, always shown on your own view.
    init(person: PersonSummary, initialDay: Int? = nil, part: PersonViewPart = .all) {
        self.init(person: person, initialDay: initialDay, part: part) {
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
