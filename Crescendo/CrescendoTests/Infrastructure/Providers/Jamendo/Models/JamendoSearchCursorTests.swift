import Foundation
import Testing

@testable import Crescendo

struct JamendoSearchCursorTests {
    @Test
    func cursorRoundTripsQueryAndOffset() throws {
        let cursor = JamendoSearchCursor(query: "jazz", offset: 20)
        let searchCursor = try cursor.searchCursor()

        #expect(try JamendoSearchCursor(searchCursor: searchCursor) == cursor)
    }

    @Test
    func malformedBase64ThrowsUnavailable() {
        let malformedCursor = SearchCursor(value: "not-valid-base64!!!")

        #expect(throws: MusicProviderError.unavailable) {
            try JamendoSearchCursor(searchCursor: malformedCursor)
        }
    }

    @Test
    func validBase64ButNonJSONThrowsUnavailable() {
        let nonJSONData = Data("hello world this is not json".utf8)
        let cursor = SearchCursor(value: nonJSONData.base64EncodedString())

        #expect(throws: MusicProviderError.unavailable) {
            try JamendoSearchCursor(searchCursor: cursor)
        }
    }

    @Test
    func validJSONMissingExpectedKeysThrowsUnavailable() {
        let wrongShapeData = Data("{\"foo\":1}".utf8)
        let cursor = SearchCursor(value: wrongShapeData.base64EncodedString())

        #expect(throws: MusicProviderError.unavailable) {
            try JamendoSearchCursor(searchCursor: cursor)
        }
    }
}
