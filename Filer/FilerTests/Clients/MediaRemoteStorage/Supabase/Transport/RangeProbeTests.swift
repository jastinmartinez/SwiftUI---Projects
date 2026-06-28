@testable import Filer
import Foundation
import Testing

struct RangeProbeTests {
    @Test func status206SignalsRangeSupport() {
        let probe = RangeProbe.parse(response(status: 206, headers: ["Content-Range": "bytes 0-0/12345"]))
        #expect(probe.supportsRanges)
    }

    @Test func acceptRangesBytesSignalsRangeSupport() {
        let probe = RangeProbe.parse(response(status: 200, headers: ["Accept-Ranges": "bytes"]))
        #expect(probe.supportsRanges)
    }

    @Test func plain200WithoutAcceptRangesDoesNotSupportRanges() {
        let probe = RangeProbe.parse(response(status: 200, headers: ["Content-Length": "12345"]))
        #expect(!probe.supportsRanges)
    }

    @Test func totalLengthComesFromContentRangeTotal() {
        let probe = RangeProbe.parse(response(status: 206, headers: [
            "Content-Range": "bytes 0-0/98765",
            "Content-Length": "1", // must NOT win — Content-Range total is authoritative
        ]))
        #expect(probe.totalLength == 98765)
    }

    @Test func totalLengthFallsBackToContentLength() {
        let probe = RangeProbe.parse(response(status: 200, headers: ["Content-Length": "54321"]))
        #expect(probe.totalLength == 54321)
    }

    @Test func totalLengthNilWhenNeitherHeaderPresent() {
        let probe = RangeProbe.parse(response(status: 200, headers: [:]))
        #expect(probe.totalLength == nil)
    }

    // MARK: - Helpers

    private func response(status: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://xyz.supabase.co/object")!,
            statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
    }
}
