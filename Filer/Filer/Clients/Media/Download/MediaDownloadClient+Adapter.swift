import Foundation

extension MediaDownloadClient {
    /// Parsed HTTP `Content-Range` header value (`bytes start-end/total`).
    struct ContentRange: Equatable, Sendable {
        let start: UInt64
        let end: UInt64
        let total: UInt64?

        static func parse(_ value: String?) -> ContentRange? {
            guard let value else { return nil }

            let fields = value.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields.first == "bytes" else { return nil }
            let rangeAndTotal = fields[1].split(
                separator: "/",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard rangeAndTotal.count == 2 else { return nil }

            let bounds = rangeAndTotal[0].split(
                separator: "-",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard
                bounds.count == 2,
                let startText = bounds.first,
                let endText = bounds.dropFirst().first,
                let start = UInt64(startText),
                let end = UInt64(endText),
                start <= end
            else {
                return nil
            }

            let totalText = rangeAndTotal[1]
            if totalText == "*" {
                return ContentRange(start: start, end: end, total: nil)
            }
            guard let total = UInt64(totalText) else { return nil }
            return ContentRange(start: start, end: end, total: total)
        }
    }
}

extension MediaDownloadClient.ProbeResult {
    /// Adapts a raw `HTTPResponse` into a probe result (range support + total length).
    init(response: HTTPResponse) {
        statusCode = response.statusCode
        supportsRanges =
            response.statusCode == 206
                || response.value(forHeader: "Accept-Ranges")?.lowercased() == "bytes"
        if let contentRange = response.value(forHeader: "Content-Range") {
            totalLength = MediaDownloadClient.ContentRange.parse(contentRange)?.total.flatMap { Int64(exactly: $0) }
        } else {
            totalLength = response.value(forHeader: "Content-Length").flatMap(Int64.init)
        }
        body = response.body
    }
}
