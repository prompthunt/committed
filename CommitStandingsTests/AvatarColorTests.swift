import Testing
import SwiftUI
@testable import CommitStandings

struct AvatarColorTests {

    @Test func colorIsStableForSameUsername() {
        // The FNV-1a hash is purely a function of the bytes, so calling it
        // many times in the same process must produce identical results.
        let a = AvatarColor.color(for: "addisonk")
        let b = AvatarColor.color(for: "addisonk")
        #expect(a == b)
    }

    @Test func colorDiffersAcrossDifferentUsernames() {
        // Not a strict requirement, but the palette is wide enough that a
        // handful of common handles should not all collide.
        let samples = ["addisonk", "octocat", "torvalds", "satya", "ada"].map(AvatarColor.color(for:))
        #expect(Set(samples).count >= 3)
    }

    @Test func initialsHandleSingleAndHyphenatedNames() {
        #expect(AvatarColor.initials(for: "addisonk") == "AD")
        #expect(AvatarColor.initials(for: "ada-lovelace") == "AL")
        #expect(AvatarColor.initials(for: "z") == "Z")
    }
}
