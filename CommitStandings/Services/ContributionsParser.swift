import Foundation

/// Parses GitHub's public contributions calendar HTML at
/// `https://github.com/users/{username}/contributions` into per-day
/// contribution counts and computes a daily, trailing-7-day, or trailing-30-day sum.
///
/// The HTML has shifted shape multiple times. We support two forms:
///
/// 1. Modern (2024+): `<td data-date="YYYY-MM-DD" id="...">` paired with a
///    `<tool-tip for="...">N contributions on ...</tool-tip>` element, where
///    "No contributions" → 0.
/// 2. Legacy: `<td data-date="YYYY-MM-DD" data-count="N">`, or a sibling
///    `<span aria-label="N contributions on ...">`.
enum ContributionsParser {
    static func parseDays(html: String) throws -> [Date: Int] {
        let cells = extractDateCells(html: html)
        if cells.isEmpty {
            throw ContributionsError.parseFailed("No day cells found")
        }
        let tooltipCounts = extractTooltipCounts(html: html)
        let calendar = contributionCalendar()

        var result: [Date: Int] = [:]
        for cell in cells {
            guard let day = calendar.date(from: cell.dateComponents) else { continue }
            let normalized = calendar.startOfDay(for: day)
            if let direct = cell.directCount {
                result[normalized] = direct
            } else if let id = cell.id, let count = tooltipCounts[id] {
                result[normalized] = count
            } else if let labelCount = cell.ariaLabelCount {
                result[normalized] = labelCount
            } else {
                result[normalized] = 0
            }
        }
        if result.isEmpty {
            throw ContributionsError.parseFailed("No day counts resolved")
        }
        return result
    }

    static func sum(days: [Date: Int], window: ContributionWindow, asOf reference: Date) -> Int {
        let calendar = contributionCalendar()
        let today = calendar.startOfDay(for: reference)
        guard let earliest = calendar.date(byAdding: .day, value: -(window.dayCount - 1), to: today) else {
            return 0
        }
        var sum = 0
        for (date, count) in days where date >= earliest && date <= today {
            sum += count
        }
        return sum
    }

    // MARK: - Internals

    static func contributionCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func isoCalendar() -> Calendar {
        contributionCalendar()
    }

    struct DateCell {
        var dateComponents: DateComponents
        var id: String?
        var directCount: Int?
        var ariaLabelCount: Int?
    }

    private static let dateAttrRegex = try! NSRegularExpression(
        pattern: #"<td\b([^>]*)\bdata-date=\"(\d{4})-(\d{2})-(\d{2})\"([^>]*)>([\s\S]*?)</td>"#,
        options: [.caseInsensitive]
    )

    private static let idAttrRegex = try! NSRegularExpression(
        pattern: #"\bid=\"([^\"]+)\""#,
        options: [.caseInsensitive]
    )

    private static let dataCountRegex = try! NSRegularExpression(
        pattern: #"\bdata-count=\"(\d+)\""#,
        options: [.caseInsensitive]
    )

    private static let ariaLabelRegex = try! NSRegularExpression(
        pattern: #"aria-label=\"([^\"]+)\""#,
        options: [.caseInsensitive]
    )

    private static let tooltipRegex = try! NSRegularExpression(
        pattern: #"<tool-tip\b[^>]*\bfor=\"([^\"]+)\"[^>]*>([\s\S]*?)</tool-tip>"#,
        options: [.caseInsensitive]
    )

    private static let leadingCountRegex = try! NSRegularExpression(
        pattern: #"^\s*([\d,]+)\s+contribution"#,
        options: [.caseInsensitive]
    )

    private static let noContribRegex = try! NSRegularExpression(
        pattern: #"^\s*no\s+contributions"#,
        options: [.caseInsensitive]
    )

    private static func extractDateCells(html: String) -> [DateCell] {
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = dateAttrRegex.matches(in: html, options: [], range: range)
        var cells: [DateCell] = []
        for m in matches {
            guard m.numberOfRanges >= 7 else { continue }
            let preAttrs = ns.substring(with: m.range(at: 1))
            let yearStr = ns.substring(with: m.range(at: 2))
            let monthStr = ns.substring(with: m.range(at: 3))
            let dayStr = ns.substring(with: m.range(at: 4))
            let postAttrs = ns.substring(with: m.range(at: 5))
            let body = ns.substring(with: m.range(at: 6))
            guard let year = Int(yearStr), let month = Int(monthStr), let day = Int(dayStr) else { continue }
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day

            let combinedAttrs = preAttrs + " " + postAttrs
            var cell = DateCell(dateComponents: comps, id: nil, directCount: nil, ariaLabelCount: nil)
            if let id = firstCapture(regex: idAttrRegex, in: combinedAttrs) {
                cell.id = id
            }
            if let countStr = firstCapture(regex: dataCountRegex, in: combinedAttrs),
               let count = Int(countStr) {
                cell.directCount = count
            }
            if let label = firstCapture(regex: ariaLabelRegex, in: combinedAttrs) {
                cell.ariaLabelCount = parseCount(fromLabel: label)
            } else if let label = firstCapture(regex: ariaLabelRegex, in: body) {
                cell.ariaLabelCount = parseCount(fromLabel: label)
            }
            cells.append(cell)
        }
        return cells
    }

    private static func extractTooltipCounts(html: String) -> [String: Int] {
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = tooltipRegex.matches(in: html, options: [], range: range)
        var byID: [String: Int] = [:]
        for m in matches {
            guard m.numberOfRanges >= 3 else { continue }
            let forID = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2))
            byID[forID] = parseCount(fromLabel: body) ?? 0
        }
        return byID
    }

    private static func parseCount(fromLabel label: String) -> Int? {
        if noContribRegex.firstMatch(in: label, options: [], range: NSRange(location: 0, length: (label as NSString).length)) != nil {
            return 0
        }
        if let captured = firstCapture(regex: leadingCountRegex, in: label) {
            let digits = captured.replacingOccurrences(of: ",", with: "")
            return Int(digits)
        }
        return nil
    }

    private static func firstCapture(regex: NSRegularExpression, in text: String) -> String? {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: text, options: [], range: range), m.numberOfRanges >= 2 else {
            return nil
        }
        return ns.substring(with: m.range(at: 1))
    }
}
