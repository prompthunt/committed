#if DEBUG
import Foundation
import UIKit

/// Debug builds only: launch with `-ScreenshotFixture` to run the real app on a fixed, offline
/// board (no GitHub account, no network) for screenshots and visual checks:
///
///     xcrun simctl launch <udid> com.addisonk.CommitStandings.iOS -ScreenshotFixture
///
/// Optional, after `-ScreenshotFixture`: `-ScreenshotTab people|settings` opens on that tab,
/// `-ScreenshotHide <login>` hides that person before the first refresh (so Today still moves),
/// `-ScreenshotPin <login,login>` pins those people as rivals (Your rivals on the Board),
/// `-ScreenshotRivalLimit` shows Rival's "You can pin up to 3 rivals" on a person view opened with
/// three rivals already pinned, as a tap would,
/// `-ScreenshotWindow <raw value>` opens the board on that Window (`monthly` for 30 days),
/// `-ScreenshotDate <ISO 8601>` sets the app's clock, `-ScreenshotShare` opens Share board once the
/// board has loaded,
/// `-ScreenshotPerson <login>` opens that person's view (pushed onto the Board, or the second pane on the open
/// iPhone Duo) and `-ScreenshotPersonDay <n>` selects that day's bar instead of today's
/// (`-ScreenshotPersonEnd` scrolls it to the end), `-ScreenshotChallenge <login>` opens that person's
/// view and their Challenge share once their race loads (as a notification's Share your race does),
/// `-ScreenshotNotificationResponse <action>:<login>` responds to a relay pass notification at launch,
/// `-ScreenshotTroll <login>` gives that person an observed burst (784 more between reads, the troll face),
/// `-ScreenshotCalendarFrom <login>=<YYYY-MM-DD>` starts that person's calendar on that day once the
/// board loads (empty weeks in their Weekly record),
/// `-ScreenshotRecordDay <n>` makes your count today n (a big one sets a record: the record card
/// and New tiles in Your records; `-ScreenshotShareRecord` then taps the card's Share), `-ScreenshotHide` takes several logins separated by commas,
/// `-ScreenshotCountScale <n>` multiplies everyone's counts by n (30 puts every 30-day count in
/// the thousands beside the streaks, the board's widest rows), and
/// `-LiveRankPayload <file.json>` shows a Live Activity push payload's content state in Live rank,
/// `-ScreenshotNotifications` opens Settings ▸ Notifications (with `-ScreenshotTab settings`;
/// `-ScreenshotNotificationsEnd` scrolls it to Delivery),
/// `-ScreenshotPasses rivals`, `-ScreenshotCloseCalls`, `-ScreenshotResults off`, `-ScreenshotRecords off`,
/// `-ScreenshotStreakReminder`, `-ScreenshotDelivery immediate` and `-ScreenshotQuietHours 23:30-07:00`
/// (or `off`) set the board owner's notification choices,
/// `-ScreenshotNotificationsDenied` reads iOS's permission as denied,
/// `-ScreenshotNoRelay` runs a relay build as one without the relay,
/// and `-RelayDisclosureAccepted` starts with the Committed relay disclosure already accepted (for
/// builds with `COMMITTED_RELAY_URL`; without it, a relay build shows the disclosure sheet).
///
/// The data is the Sample board's (`SampleServices`); everything above it is real:
/// `CommittedServices`, `RefreshCoordinator`, `Ranking`, and every view. Counts move between the
/// first two refreshes so Today shows movement chevrons. One person always fails to load, to show
/// the missing-data placeholder.
@MainActor
enum ScreenshotFixture {
    static let launchArgument = "-ScreenshotFixture"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// The tab to open on, from `-ScreenshotTab board|people|settings`. Honored on any Debug
    /// launch, so captures of the Sample board (which persists) can open on People or Settings too.
    static var requestedTab: AppTab? {
        switch value(after: "-ScreenshotTab") {
        case "board": return .board
        case "people": return .people
        case "settings": return .settings
        default: return nil
        }
    }

    /// `-ScreenshotPerson <login>`: the person view to open on launch, as a tap on their row would.
    static var requestedPerson: String? {
        value(after: "-ScreenshotPerson")
    }

    /// `-ScreenshotChallenge <login>`: opens that person's view and presents their Challenge share
    /// once their race has loaded, through `AppModel.requestChallenge`.
    static var requestedChallenge: String? {
        value(after: "-ScreenshotChallenge")
    }

    /// `-ScreenshotNotificationResponse <action>:<login>`: at launch, a response to a relay pass
    /// notification about `login`, as if `action` (`SHARE_RACE`, `OPEN_BOARD`, or iOS's body-tap
    /// identifier) had been chosen with Committed closed. Once the fixture's people load, it goes
    /// through the notification delegate's own route (`ForegroundNotificationPresenter.receive`).
    /// No notification is shown or tapped. `-ScreenshotNotificationKind closeCall` makes it a relay
    /// close call (#132) instead, which has no category; `streakReminder` a streak reminder (#133),
    /// whose login is your own; `summary` the evening summary (#135), which names no one (the login
    /// is ignored).
    static var notificationResponse: DeepLink? {
        guard let raw = value(after: "-ScreenshotNotificationResponse"),
              let colon = raw.lastIndex(of: ":") else { return nil }
        let action = String(raw[..<colon]), login = String(raw[raw.index(after: colon)...])
        let kind = value(after: "-ScreenshotNotificationKind").flatMap(DeepLink.NotificationKind.init(rawValue:)) ?? .pass
        switch kind {
        case .summary, .result:
            return DeepLink(notification: ["kind": kind.rawValue], action: action)
        case .closeCall, .record, .streakReminder:
            return DeepLink(notification: ["kind": kind.rawValue, "login": login], action: action)
        case .pass:
            return DeepLink(notification: ["kind": kind.rawValue, "login": login, "aps": ["category": DeepLink.passCategory]],
                            action: action)
        }
    }

    /// `-ScreenshotPersonDay <n>`: the person view's selected bar, instead of today's.
    static var personDay: Int? {
        value(after: "-ScreenshotPersonDay").flatMap(Int.init)
    }

    /// `-ScreenshotPersonEnd`: the person view opens scrolled to its end (your own view's tip and
    /// note).
    static var personScrolledToEnd: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotPersonEnd")
    }

    /// `-ScreenshotSheetEnd`: the relay sheets open scrolled to their end, so captures on the closed
    /// iPhone Duo show their last lines (the notifications line).
    static var sheetScrolledToEnd: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotSheetEnd")
    }

    /// `-ScreenshotConnect`: start Connect GitHub on launch, as a tap would, so captures can show
    /// its code (for example over the Sample board). Honored on any Debug launch. It asks GitHub
    /// for a real device code; nothing connects unless someone approves it.
    static var startsConnect: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotConnect")
    }

    /// `-ScreenshotShare`: open Share board a few seconds after launch, once the first refresh has
    /// loaded the board, as tapping Share would, so captures can show the sheet. Honored on any
    /// Debug launch.
    static var opensShare: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotShare")
    }

    /// `-ScreenshotFaceOff`: open Share face-off a few seconds after launch on the person view that
    /// `-ScreenshotPerson` opened, as tapping its share icon would; `-ScreenshotFaceOffStory` starts
    /// it on Story instead of Square. Honored on any Debug launch.
    static var opensFaceOff: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotFaceOff")
    }

    static var faceOffFormat: BoardShareFormat {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotFaceOffStory") ? .story : .square
    }

    /// `-ScreenshotShareRecord`: tap the record card's Share a few seconds after launch, once the
    /// board has loaded, so captures can show the share sheet with the card's image.
    static var sharesRecord: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotShareRecord")
    }

    /// `-ScreenshotRivalLimit`: a person view's Rival explains the limit on appear when three rivals
    /// are pinned, as tapping it would. Honored on any Debug launch.
    static var explainsRivalLimit: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotRivalLimit")
    }

    /// `-ScreenshotNotifications`: Settings opens on the Notifications screen.
    static var opensNotifications: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotNotifications")
    }

    /// `-ScreenshotNotificationsEnd`: the Notifications screen scrolls to Delivery (and Quiet hours
    /// below it) once it loads, for captures of sections below the fold.
    static var notificationsScrolledToEnd: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotNotificationsEnd")
    }

    /// `-ScreenshotNotificationsAboutYou`: the Notifications screen scrolls to About you once it loads.
    static var notificationsScrolledToAboutYou: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotNotificationsAboutYou")
    }

    /// `-ScreenshotNotificationsDenied`: iOS's notification permission reads as denied.
    static var notificationsDenied: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotNotificationsDenied")
    }

    /// `-ScreenshotNoRelay`: no Committed relay, even in a relay build.
    static var withoutRelay: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotNoRelay")
    }

    /// The board owner's notification choices, in memory: the defaults, with `-ScreenshotPasses`,
    /// `-ScreenshotCloseCalls` (Close calls on), `-ScreenshotResults off`, `-ScreenshotRecords off`,
    /// `-ScreenshotStreakReminder` (Streak reminder on), `-ScreenshotDelivery immediate|summary` and
    /// `-ScreenshotQuietHours <start>-<end>|off` applied.
    static func notificationPreferences() -> InMemoryNotificationPreferences {
        var choices = NotificationPreferences()
        if let passes = value(after: "-ScreenshotPasses").flatMap(NotificationPreferences.Passes.init(rawValue:)) {
            choices.passes = passes
        }
        if ProcessInfo.processInfo.arguments.contains("-ScreenshotCloseCalls") {
            choices.closeCalls = true
        }
        if value(after: "-ScreenshotRecords") == "off" {
            choices.records = false
        }
        if ProcessInfo.processInfo.arguments.contains("-ScreenshotStreakReminder") {
            choices.streakReminder = true
        }
        if let hours = value(after: "-ScreenshotQuietHours") {
            let ends = hours.split(separator: "-").map(String.init)
            choices.quietHours = ends.count == 2 ? .init(start: ends[0], end: ends[1]) : nil
        }
        if value(after: "-ScreenshotResults") == "off" { choices.results = false }
        if let delivery = value(after: "-ScreenshotDelivery").flatMap(NotificationPreferences.Delivery.init(rawValue:)) {
            choices.delivery = delivery
        }
        return InMemoryNotificationPreferences([SampleServices.owner: choices])
    }

    /// Live rank settings for the fixture, in memory: never chosen, or accepted and on with
    /// `-RelayDisclosureAccepted` (the earlier sheet, as 1.0.x saved it). Add
    /// `-RelayNotificationsAccepted` to have agreed to relay notifications too. With Leaderboard
    /// Notifications on (`-notifyOnPositionChange YES`), the earlier sheet alone shows "Get
    /// notifications with Committed closed?".
    static func liveRankPreferences() -> InMemoryLiveRankPreferences {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-RelayDisclosureAccepted") else {
            return InMemoryLiveRankPreferences()
        }
        let notifications: Bool? = arguments.contains("-RelayNotificationsAccepted") ? true : nil
        return InMemoryLiveRankPreferences(LiveRankPreferences(
            isEnabled: true, relayDisclosureAccepted: true, relayNotifications: notifications
        ))
    }

    /// `-ScreenshotCalendarFrom <login>=<YYYY-MM-DD>`: once the board loads, that person's calendar
    /// starts on that day, as a new GitHub account's would, so their Weekly record has empty weeks.
    /// The next refresh restores it.
    static var calendarStart: (login: String, first: String)? {
        guard let parts = value(after: "-ScreenshotCalendarFrom")?.split(separator: "="), parts.count == 2
        else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// `-LiveRankPayload <file.json>`: a Live Activity push payload, the same file you'd give
    /// `xcrun simctl push` (`aps.content-state`). This machine's `simctl push` only delivers
    /// ordinary notifications, so the app applies the payload's content state itself: Live rank
    /// runs its real lifecycle, but shows the payload instead of the derived state.
    static func liveRankActivities(_ base: any LiveRankActivities) -> any LiveRankActivities {
        guard let path = value(after: "-LiveRankPayload"),
              let data = FileManager.default.contents(atPath: path),
              let payload = try? JSONDecoder().decode(LiveRankPayload.self, from: data) else { return base }
        return PayloadLiveRankActivities(base: base, state: payload.aps.contentState)
    }

    private struct LiveRankPayload: Decodable {
        struct APS: Decodable {
            let contentState: LiveRankState
            enum CodingKeys: String, CodingKey { case contentState = "content-state" }
        }
        let aps: APS
    }

    private final class PayloadLiveRankActivities: LiveRankActivities {
        let base: any LiveRankActivities
        let state: LiveRankState
        init(base: any LiveRankActivities, state: LiveRankState) { self.base = base; self.state = state }

        var areActivitiesEnabled: Bool { base.areActivitiesEnabled }
        func current() -> [LiveRankActivity] { base.current() }
        func start(_ attributes: LiveRankAttributes, state _: LiveRankState, pushUpdates: LiveRankPushUpdates) throws
            -> LiveRankActivity {
            try base.start(attributes, state: state, pushUpdates: pushUpdates)
        }
        func update(id: String, to _: LiveRankState) async { await base.update(id: id, to: state) }
        func end(id: String) async { await base.end(id: id) }
    }

    /// Avatars for the fixture's made-up people: generated identicons (GitHub's default-avatar
    /// pattern, seeded by login) saved to the App Group cache like real ones, so the board and
    /// Live rank show the avatar shape without any real account's photo.
    static func avatars(cache: AvatarCache = .shared) -> any AvatarPrefetching {
        let avatars = GeneratedAvatars(cache: cache)
        // Saved before the first frame, so the board shows them from the start, not only after
        // a refresh re-renders its rows.
        for login in SampleServices.people + [SampleServices.failingCompetitor] {
            cache.store(GeneratedAvatars.identicon(for: login), for: login)
        }
        return avatars
    }

    struct GeneratedAvatars: AvatarPrefetching {
        let cache: AvatarCache

        func prefetch(_ logins: [String]) async {
            for login in logins {
                cache.store(Self.identicon(for: login), for: login)
            }
        }

        /// A 5×5 left-right symmetric pattern in one hue on a light ground, from a hash of the login.
        static func identicon(for login: String) -> Data {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
            for byte in login.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
            let hue = CGFloat(hash % 360) / 360
            let ink = UIColor(hue: hue, saturation: 0.55, brightness: 0.78, alpha: 1)
            let side = CGFloat(AvatarCache.pixelSize)
            let cell = side / 6
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { context in
                UIColor(white: 0.94, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
                ink.setFill()
                for row in 0..<5 {
                    for column in 0..<3 where (hash >> UInt64(8 + row * 3 + column)) & 1 == 1 {
                        for x in Set([column, 4 - column]) {
                            context.fill(CGRect(x: cell / 2 + CGFloat(x) * cell, y: cell / 2 + CGFloat(row) * cell,
                                                width: cell, height: cell))
                        }
                    }
                }
            }
        }
    }

    /// The app's clock: `-ScreenshotDate <ISO 8601>`, or the real time.
    static var now: @Sendable () -> Date {
        let date = value(after: "-ScreenshotDate").flatMap { try? Date($0, strategy: .iso8601) }
        return { date ?? Date() }
    }

    /// The Sample board's services (`SampleServices`) with the fixture's extras: one person who
    /// always fails to load, `-ScreenshotRestrictedOrg <name>`, `-ScreenshotHide <login>` and
    /// `-ScreenshotPin <login,login>`. It
    /// loads at once, refreshing twice so Today shows movement chevrons.
    ///
    /// `extraPeople` adds that many followed people (`sample-pal-01`, …) below everyone else, for a
    /// board long enough to scroll on the open iPhone Duo display (used by the #46 render tests).
    static func services(extraPeople: Int = 0, failingCompetitor: Bool = true) -> CommittedServices {
        // `-ScreenshotRestrictedOrg <name>`: an organization that won't list its members for
        // Committed, as People shows it.
        let services = SampleServices.make(SampleServices.Options(
            extraPeople: extraPeople,
            includesFailingCompetitor: failingCompetitor,
            restrictedOrganizations: value(after: "-ScreenshotRestrictedOrg").map { [$0] },
            trollPerson: value(after: "-ScreenshotTroll"),
            countScale: value(after: "-ScreenshotCountScale").flatMap(Int.init).map { max(1, $0) } ?? 1,
            recordDay: value(after: "-ScreenshotRecordDay").flatMap(Int.init)
        ), now: now)
        let hide = value(after: "-ScreenshotHide")?.split(separator: ",").map(String.init)
        let pins = value(after: "-ScreenshotPin")?.split(separator: ",").map(String.init) ?? []
        // `-ScreenshotWindow monthly`: the board opens on that Window (a raw value).
        if let window = value(after: "-ScreenshotWindow").flatMap(ContributionWindow.init(rawValue:)) {
            services.store.selectedWindow = window
        }
        Task {
            await services.auth.refreshIdentity()
            if hide != nil || !pins.isEmpty {
                await services.roster.refresh(force: true)
            }
            for login in hide ?? [] {
                services.store.setHidden(true, username: login)
            }
            for login in pins {
                services.store.setPinned(true, username: login)
            }
            // Two refreshes on the same day: the first sets today's baseline, the second moves.
            await services.refresh.refreshAll(reason: .manual)
            await services.refresh.refreshAll(reason: .timer)
            if let start = calendarStart, var history = services.store.history(for: start.login) {
                history.days = history.days.filter { $0.key >= start.first }
                services.store.updateHistories([start.login: history])
            }
        }
        return services
    }
}
#endif
