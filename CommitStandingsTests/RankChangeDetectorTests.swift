import Testing
@testable import CommitStandings

struct RankChangeDetectorTests {

    @Test func rivalPassesMe() {
        let events = RankChangeDetector.crossings(
            previous: ["me": 5, "a": 3],
            current: ["me": 5, "a": 7],
            selfUsername: "me")
        #expect(events == [RankChangeEvent(
            rivalUsername: "a", direction: .rivalPassedMe,
            rivalContributions: 7, myContributions: 5)])
    }

    @Test func iPassARival() {
        let events = RankChangeDetector.crossings(
            previous: ["me": 3, "a": 6],
            current: ["me": 8, "a": 6],
            selfUsername: "me")
        #expect(events == [RankChangeEvent(
            rivalUsername: "a", direction: .iPassedRival,
            rivalContributions: 6, myContributions: 8)])
    }

    @Test func noRelativeChangeProducesNothing() {
        let events = RankChangeDetector.crossings(
            previous: ["me": 5, "a": 3, "b": 9],
            current: ["me": 6, "a": 4, "b": 10],
            selfUsername: "me")
        #expect(events.isEmpty)
    }

    @Test func firstSnapshotProducesNothing() {
        let events = RankChangeDetector.crossings(
            previous: nil,
            current: ["me": 5, "a": 7],
            selfUsername: "me")
        #expect(events.isEmpty)
    }

    @Test func selfMissingFromEitherSnapshotProducesNothing() {
        #expect(RankChangeDetector.crossings(
            previous: ["a": 3],            // no "me"
            current: ["me": 5, "a": 7],
            selfUsername: "me").isEmpty)
        #expect(RankChangeDetector.crossings(
            previous: ["me": 5, "a": 3],
            current: ["a": 7],             // no "me"
            selfUsername: "me").isEmpty)
    }

    @Test func sustainedTieDoesNotFire() {
        // Rival catches up to an exact tie — no pass yet.
        let events = RankChangeDetector.crossings(
            previous: ["me": 5, "a": 3],
            current: ["me": 5, "a": 5],
            selfUsername: "me")
        #expect(events.isEmpty)
    }

    @Test func crossingThroughATieFiresOnce() {
        // Was tied, now strictly above → counts as passing me.
        let events = RankChangeDetector.crossings(
            previous: ["me": 5, "a": 5],
            current: ["me": 5, "a": 6],
            selfUsername: "me")
        #expect(events == [RankChangeEvent(
            rivalUsername: "a", direction: .rivalPassedMe,
            rivalContributions: 6, myContributions: 5)])
    }

    @Test func addedCompetitorIsIgnored() {
        // "a" only exists in current — even though above me, no event (not in both snapshots).
        let events = RankChangeDetector.crossings(
            previous: ["me": 5],
            current: ["me": 5, "a": 9],
            selfUsername: "me")
        #expect(events.isEmpty)
    }

    @Test func removedCompetitorIsIgnored() {
        let events = RankChangeDetector.crossings(
            previous: ["me": 5, "a": 9],
            current: ["me": 5],
            selfUsername: "me")
        #expect(events.isEmpty)
    }

    @Test func multipleSimultaneousCrossingsInDeterministicOrder() {
        // a passes me (3→9), b drops below me (8→2).
        let events = RankChangeDetector.crossings(
            previous: ["me": 5, "a": 3, "b": 8],
            current: ["me": 5, "a": 9, "b": 2],
            selfUsername: "me")
        #expect(events == [
            RankChangeEvent(rivalUsername: "a", direction: .rivalPassedMe,
                            rivalContributions: 9, myContributions: 5),
            RankChangeEvent(rivalUsername: "b", direction: .iPassedRival,
                            rivalContributions: 2, myContributions: 5),
        ])
    }
}
