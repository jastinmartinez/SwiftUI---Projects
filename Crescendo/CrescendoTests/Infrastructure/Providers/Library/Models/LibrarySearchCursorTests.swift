import Foundation
import Testing

@testable import Crescendo

struct LibrarySearchCursorTests {
    @Test
    func cursorRoundTripsQueryAndOffset() throws {
        let cursor = LibrarySearchCursor(
            query: "  dream pop  ",
            offset: 37
        )

        let searchCursor = try cursor.searchCursor()

        #expect(try LibrarySearchCursor(searchCursor: searchCursor) == cursor)
    }

    @Test
    func malformedBase64ThrowsUnavailable() {
        let cursor = SearchCursor(value: "not-valid-base64!!!")

        #expect(throws: MusicProviderError.unavailable) {
            try LibrarySearchCursor(searchCursor: cursor)
        }
    }

    @Test
    func malformedPayloadThrowsUnavailable() {
        let malformedPayload = Data("not a cursor".utf8)
        let cursor = SearchCursor(
            value: malformedPayload.base64EncodedString()
        )

        #expect(throws: MusicProviderError.unavailable) {
            try LibrarySearchCursor(searchCursor: cursor)
        }
    }
}
