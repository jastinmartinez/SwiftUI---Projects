import Foundation
import Testing

@testable import Crescendo

struct AudiusSearchCursorTests {
    @Test
    func cursorRoundTripsQueryAndOffset() throws {
        let cursor = AudiusSearchCursor(query: "ambient", offset: 40)
        let searchCursor = try cursor.searchCursor()

        #expect(try AudiusSearchCursor(searchCursor: searchCursor) == cursor)
    }

    @Test
    func malformedPayloadsThrowUnavailable() {
        let malformedBase64 = SearchCursor(value: "not-base64!!!")
        let nonJSON = SearchCursor(
            value: Data("not-json".utf8).base64EncodedString()
        )
        let wrongShape = SearchCursor(
            value: Data("{\"page\":2}".utf8).base64EncodedString()
        )

        for cursor in [malformedBase64, nonJSON, wrongShape] {
            #expect(throws: MusicProviderError.unavailable) {
                try AudiusSearchCursor(searchCursor: cursor)
            }
        }
    }
}
