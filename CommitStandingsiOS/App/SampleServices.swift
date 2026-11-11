import Foundation

/// The Sample board's data layer: `CommittedServices` on built-in people and counts, held in
/// memory, with nothing sent over the network. Every view and rule above it is real
/// (`RefreshCoordinator`, `Ranking`, the roster, Leaderboard Notifications), so the Sample board
/// and the App Store screenshots (the Debug `-ScreenshotFixture`) show the app as it works.
///
/// - No GitHub API: the contributions client, People and the device flow are local. The
///   identity call (`/user`) is answered in process as Ari Linden; anything else fails as if
///   offline.
/// - No relay and no avatars: those belong to `AppModel`, which must pair sample services with
///   `NoLiveRankRelay` and network avatars off (`loadsGitHubAvatars`).
/// - Nothing reaches the real saved board: the standings, people, hidden people and token all
///   live in memory. Leaderboard Notifications keep their real on/off setting.
///
/// `make` is inert: the board loads when something refreshes it (`AppModel.sceneDidBecomeActive`,
/// pull to refresh). Today moves between the first two fetches: Ari Linden passes Ezra Q.
@MainActor
enum SampleServices {
    /// "You" on the Sample board.
    nonisolated static let owner = "ari-linden"
    nonisolated static let ownerName = "Ari Linden"
    /// Everyone on the Sample board, you included, in board order on Today before it moves.
    nonisolated static let people = ["ines-volk", "odile-m", "ezra-q", owner, "bram-ott"]
    /// Listed in People but never loads, to show the missing-data placeholder. Screenshot fixture
    /// only; off on the Sample board.
    nonisolated static let failingCompetitor = "niko-vane"
    /// The prefix of `Options.extraPeople`: `sample-pal-01`, `sample-pal-02`, …
    nonisolated static let extraPersonPrefix = "sample-pal-"

    struct Options {
        /// That many more followed people (`sample-pal-01`, …) below everyone else, for a board long
        /// enough to scroll.
        var extraPeople = 0
        /// Adds `failingCompetitor` to the Acme organization.
        var includesFailingCompetitor = false
        /// Organizations that won't list their members for Committed, as People shows them.
        var restrictedOrganizations: [String]?
        /// This person trolls: 784 more today, far above their usual, so their row wears the troll
        /// face (screenshot fixture only).
        var trollPerson: String?
    }

    static func make(_ options: Options = Options(), now: @escaping @Sendable () -> Date = { Date() })
        -> CommittedServices {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineGitHub.self]
        let session = URLSession(configuration: config)
        let extras = (0..<options.extraPeople).map { extraPersonPrefix + String(format: "%02d", $0 + 1) }
        let organization = ["odile-m", "bram-ott"] + (options.includesFailingCompetitor ? [failingCompetitor] : [])
        let restricted = options.restrictedOrganizations
        return CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: "sample"),
            contributions: SampleContributions(trollPerson: options.trollPerson),
            // Even a stray Connect GitHub on this graph stays on the phone.
            gitHubAuth: GitHubAuth(clientID: "sample", session: session),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: owner, sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["ines-volk", "ezra-q"] + extras),
                    GitHubRosterSource(id: "org", title: "Acme", members: organization),
                ], updatedAt: now().addingTimeInterval(-240), restrictedOrganizations: restricted)
            },
            now: now
        )
    }

    /// Made-up calendars, about a year long like GitHub's, ending today in the device's time zone.
    /// Each person's totals per Window stay fixed (and the month so far too, from mid-month, when
    /// there are enough days for it, for the person view); each fetch sets today's baseline; from
    /// the second on, Ari Linden has 2 more today and passes Ezra Q. Streaks: Odile M has contributed
    /// every day of the calendar ("365+"), Ines Volk 47 days, Ari Linden 14, Ezra Q 3, and Bram Ott,
    /// with nothing yesterday or today, none. Extra people have only today, counting down from 39.
    private actor SampleContributions: ContributionsFetching {
        private var rounds: [String: Int] = [:]
        private let trollPerson: String?

        init(trollPerson: String? = nil) {
            self.trollPerson = trollPerson
        }

        func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date)
            async -> Result<StandingCounts, ContributionsError> {
            let round = rounds[username, default: 0]
            rounds[username] = round + 1
            let people: [String: SampleCalendar] = [
                "ines-volk": SampleCalendar(today: 12, week: 61, month: 240, thisMonth: 84, streak: 47, seed: 1),
                "odile-m": SampleCalendar(today: 9, week: 44, month: 198, thisMonth: 66,
                                          streak: SampleCalendar.length, seed: 2),
                "ari-linden": SampleCalendar(today: round == 0 ? 5 : 7, week: 38, month: 171,
                                             thisMonth: round == 0 ? 55 : 57, streak: 14, seed: 3),
                "ezra-q": SampleCalendar(today: 6, week: 52, month: 160, thisMonth: 56, streak: 3, seed: 4),
                "bram-ott": SampleCalendar(today: 0, week: 11, month: 57, thisMonth: 19, streak: 0, seed: 5),
            ]
            let timeZone = TimeZone.current
            var history: ContributionHistory
            if username.hasPrefix(SampleServices.extraPersonPrefix),
               let number = Int(username.dropFirst(SampleServices.extraPersonPrefix.count)) {
                history = SampleCalendar.onlyToday(max(0, 40 - number), asOf: reference, timeZone: timeZone)
            } else if let person = people[username] {
                history = person.history(asOf: reference, timeZone: timeZone)
            } else {
                return .failure(.network("offline"))
            }
            if username == trollPerson {
                // 784 more today, far above their usual: the real trolling rule marks the row.
                let key = ContributionHistory.key(for: reference, in: history.calendar)
                history.days[key, default: 0] += 784
            }
            return .success(StandingCounts(history: history, window: window, asOf: reference))
        }
    }

    /// Answers GitHub's `/user` with the sample profile, in process, and fails everything else as
    /// if offline.
    private final class OfflineGitHub: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let url = request.url, url.host == "api.github.com", url.path == "/user",
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            let body = Data(#"{"login":"\#(SampleServices.owner)","name":"\#(SampleServices.ownerName)"}"#.utf8)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}

/// One Sample board person's made-up calendar: `length` days ending today, with exactly `today`
/// today, `week` over 7 days and `month` over 30, and a current streak of `streak` days (counted
/// from yesterday when today is 0). The month so far adds up to `thisMonth` whenever it
/// has room for it between the 7- and 30-day totals (the 8th to the 29th); on other days it's
/// whatever its days add up to. Every other day is filled from `seed`, so a person's
/// calendar is the same on every fetch.
struct SampleCalendar {
    /// GitHub's calendar: 53 weeks.
    static let length = 371

    let today: Int
    let week: Int
    let month: Int
    let thisMonth: Int
    let streak: Int
    let seed: UInt64

    func history(asOf reference: Date, timeZone: TimeZone) -> ContributionHistory {
        var random = SplitMix(seed: seed)
        let first = today > 0 ? 0 : 1 // where the streak starts counting back
        // Which days have contributions: the streak, then the day that broke it, then mostly yes.
        let active: [Bool] = (0..<Self.length).map { offset in
            if offset == 0 { return today > 0 }
            if offset >= first && offset < first + streak { return true }
            if offset == first + streak { return false }
            return random.next() % 4 != 0
        }
        var counts = Array(repeating: 0, count: Self.length)
        counts[0] = today
        Self.spread(week - today, over: Array(1..<7), active: active, into: &counts, random: &random)
        // Days 7…29 back, split at the 1st of this month when the month so far's total fits there.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let monthStart = calendar.component(.day, from: reference) // offsets 0..<monthStart are this month
        if (8...29).contains(monthStart), thisMonth >= week, month >= thisMonth {
            Self.spread(thisMonth - week, over: Array(7..<monthStart), active: active, into: &counts, random: &random)
            Self.spread(month - thisMonth, over: Array(monthStart..<30), active: active, into: &counts, random: &random)
        } else {
            Self.spread(month - week, over: Array(7..<30), active: active, into: &counts, random: &random)
        }
        for offset in 30..<Self.length where active[offset] {
            counts[offset] = 1 + Int(random.next() % 9)
        }
        return Self.history(counts, asOf: reference, timeZone: timeZone)
    }

    static func onlyToday(_ count: Int, asOf reference: Date, timeZone: TimeZone) -> ContributionHistory {
        history([count], asOf: reference, timeZone: timeZone)
    }

    /// `total` across the active days among `offsets`, at least 1 each, the rest by random weight.
    private static func spread(_ total: Int, over offsets: [Int], active: [Bool], into counts: inout [Int],
                               random: inout SplitMix) {
        var days = offsets.filter { active[$0] }
        if days.isEmpty, total > 0, let last = offsets.last { days = [last] } // the segment's oldest day
        guard !days.isEmpty else { return }
        let base = min(1, total / days.count)
        let weights = days.map { _ in 1 + Int(random.next() % 8) }
        let weightSum = weights.reduce(0, +)
        var remaining = total - base * days.count
        let extra = remaining
        for (index, day) in days.enumerated() {
            let share = extra * weights[index] / weightSum
            counts[day] = base + share
            remaining -= share
        }
        counts[days[0]] += remaining
    }

    /// `counts[0]` is today; each later index is a day earlier.
    private static func history(_ counts: [Int], asOf reference: Date, timeZone: TimeZone) -> ContributionHistory {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: reference)
        var days: [String: Int] = [:]
        for (offset, count) in counts.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            days[ContributionHistory.key(for: day, in: calendar)] = count
        }
        return ContributionHistory(days: days, timeZone: timeZone)
    }

    /// A small, fixed pseudo-random sequence (SplitMix64), so made-up days never change.
    struct SplitMix {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
