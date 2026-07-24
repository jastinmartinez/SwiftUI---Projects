import Foundation
import Testing

@testable import Crescendo

struct URLHTTPTests {
    @Test(
        arguments: [
            "http://example.com",
            "https://example.com",
            "HTTP://example.com",
            "HTTPS://example.com",
        ]
    )
    func acceptsHTTPAndHTTPSSchemesCaseInsensitively(httpString: String) throws {
        let url = try #require(URL(httpString: httpString))
        let scheme = try #require(url.scheme?.lowercased())

        #expect(scheme == "http" || scheme == "https")
    }

    @Test(
        arguments: [
            "file:///etc/passwd",
            "ftp://example.com",
            "example.com",
            "",
            "not a url at all",
        ]
    )
    func rejectsNonHTTPValues(httpString: String) {
        #expect(URL(httpString: httpString) == nil)
    }
}
