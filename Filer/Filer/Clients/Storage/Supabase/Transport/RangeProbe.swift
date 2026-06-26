import Foundation

// framework → domain (init on the domain value, like FileItem(_:FileObject))
struct RangeProbe: Equatable {
    let supportsRanges: Bool // 206 from the bytes=0-0 probe is the trustworthy signal
    let totalLength: Int64?

    nonisolated init(_ response: HTTPURLResponse) {
        supportsRanges = response.statusCode == 206
            || response.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"
        totalLength = response.value(forHTTPHeaderField: "Content-Range")?
            .split(separator: "/").last.flatMap { Int64($0) } // "bytes 0-0/12345"
            ?? response.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
    }
}
