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

    @Test func dataClosureReturnsInjectedResponse() async throws {
        let url = try #require(URL(string: "https://example.com/file"))
        let transport = HTTPTransport(
            data: { _ in
                HTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Length": "3"],
                    body: Data([1, 2, 3])
                )
            },
            upload: { _, _ in
                HTTPResponse(statusCode: 204, headers: [:], body: Data())
            }
        )

        let response = try await transport.data(URLRequest(url: url))

        #expect(response.statusCode == 200)
        #expect(response.value(forHeader: "content-length") == "3")
        #expect(response.body == Data([1, 2, 3]))
    }
}
