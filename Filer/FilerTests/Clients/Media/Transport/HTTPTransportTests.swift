@testable import Filer
import Foundation
import Testing

struct HTTPTransportTests {
    @Test func responseLooksUpHeadersCaseInsensitively() {
        let response = HTTPResponse(
            statusCode: 206,
            headers: ["Content-Range": "bytes 0-0/12"],
            body: Data([1])
        )

        #expect(response.value(forHeader: "content-range") == "bytes 0-0/12")
        #expect(response.value(forHeader: "Content-Range") == "bytes 0-0/12")
        #expect(response.value(forHeader: "CONTENT-RANGE") == "bytes 0-0/12")
        #expect(response.value(forHeader: "missing") == nil)
    }
}
