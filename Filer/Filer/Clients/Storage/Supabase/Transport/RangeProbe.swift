import Foundation

enum RangeProbe {
    struct Result: Equatable, Sendable {
        let supportsRanges: Bool
        let totalLength: Int64?

        nonisolated init(supportsRanges: Bool, totalLength: Int64?) {
            self.supportsRanges = supportsRanges
            self.totalLength = totalLength
        }
    }

    nonisolated static func parse(_ response: HTTPURLResponse) -> Result {
        Result(
            supportsRanges: response.statusCode == 206
                || response.value(forHTTPHeaderField: "Accept-Ranges") == "bytes",
            totalLength: response.value(forHTTPHeaderField: "Content-Range")?
                .split(separator: "/").last.flatMap { Int64($0) }
                ?? response.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
        )
    }
}
