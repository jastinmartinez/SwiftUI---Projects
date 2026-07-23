import Testing

@testable import Crescendo

struct AppleMusicSearchCursorTests {
    @Test
    func encodedCursorPreservesQueryAndOffset() throws {
        let encoded = try AppleMusicSearchCursor(
            query: "Beyoncé & Jay-Z",
            offset: 20
        ).searchCursor()

        let decoded = try AppleMusicSearchCursor(searchCursor: encoded)

        #expect(decoded.query == "Beyoncé & Jay-Z")
        #expect(decoded.offset == 20)
    }

    @Test
    func invalidCursorIsRejected() {
        #expect(throws: (any Error).self) {
            try AppleMusicSearchCursor(
                searchCursor: SearchCursor(value: "not-json")
            )
        }
    }
}
