import Testing
@testable import CommitStandings

struct DisplayNameTests {

    @Test func fullNameReturnsFirstToken() {
        #expect(DisplayName.firstName(from: "Addison Kowalski") == "Addison")
    }

    @Test func singleTokenReturnsItself() {
        #expect(DisplayName.firstName(from: "Addison") == "Addison")
    }

    @Test func extraWhitespaceIsTrimmedAndCollapsed() {
        #expect(DisplayName.firstName(from: "  Addison   Kowalski  ") == "Addison")
    }

    @Test func emptyStringReturnsNil() {
        #expect(DisplayName.firstName(from: "") == nil)
    }

    @Test func whitespaceOnlyReturnsNil() {
        #expect(DisplayName.firstName(from: "   ") == nil)
    }

    @Test func nilReturnsNil() {
        #expect(DisplayName.firstName(from: nil) == nil)
    }
}
