import Testing
@testable import CommitStandings

struct NotificationCopyTests {

    @Test func rivalPassedMeCopy() {
        let copy = NotificationService.copy(for: RankChangeEvent(
            rivalUsername: "kropdx", direction: .rivalPassedMe,
            rivalContributions: 24, myContributions: 23))
        #expect(copy.title == "😤 kropdx passed you")
        #expect(copy.body == "They're ahead 24–23. Time to catch up!")
    }

    @Test func iPassedRivalCopy() {
        let copy = NotificationService.copy(for: RankChangeEvent(
            rivalUsername: "kropdx", direction: .iPassedRival,
            rivalContributions: 23, myContributions: 24))
        #expect(copy.title == "🎉 You passed kropdx!")
        #expect(copy.body == "You're ahead 24–23. Keep climbing!")
    }
}
