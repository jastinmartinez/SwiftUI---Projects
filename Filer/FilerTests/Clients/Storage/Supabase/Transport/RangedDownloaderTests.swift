@testable import Filer
import Foundation
import Testing

@Suite(.serialized) struct RangedDownloaderTests {
    private let source = URL(string: "https://example.supabase.co/object/public/bucket/file.bin")!

    @Test func rangedPathProbesAndWritesContiguously() async throws {
        let total = 14 * 1024 * 1024 // 6 + 6 + 2
        let chunk = TransferProgress.chunkSize
        let out = dest()
        let ranges = LockedBox<[String]>([])

        StubURLProtocol.handler = { req in
            let range = req.value(forHTTPHeaderField: "Range")
            // probe: bytes=0-0 → 206 with Content-Range total
            if range == "bytes=0-0" {
                return (Self.resp(source, 206,
                                  ["Content-Range": "bytes 0-0/\(total)", "Accept-Ranges": "bytes"]),
                        Data(repeating: 0xAB, count: 1))
            }
            ranges.mutate { $0.append(range ?? "?") }
            let parts = range!.dropFirst("bytes=".count).split(separator: "-")
            let start = Int(parts[0])!, end = Int(parts[1])!
            return (Self.resp(source, 206,
                              ["Content-Range": "bytes \(start)-\(end)/\(total)"]),
                    slice(total, start, end - start + 1))
        }
        defer { StubURLProtocol.handler = nil }

        let downloader = RangedDownloader(session: StubURLProtocol.session())
        var last: TransferProgress?
        for try await p in downloader.download(source, to: out, headers: [:],
                                               expectedSize: nil, chunkSize: chunk)
        {
            last = p
        }

        #expect(ranges.value == [
            "bytes=0-\(chunk - 1)",
            "bytes=\(chunk)-\(2 * chunk - 1)",
            "bytes=\(2 * chunk)-\(total - 1)",
        ])
        #expect(last?.bytesTransferred == Int64(total))
        #expect(last?.totalBytes == Int64(total)) // authoritative total from probe (expectedSize nil)
        let written = try Data(contentsOf: out)
        #expect(written.count == total)
    }

    @Test func streamingFallbackUsesContentLength() async throws {
        let total = 5 * 1024 * 1024
        let out = dest()

        StubURLProtocol.handler = { req in
            // probe: server ignores Range → 200, no Accept-Ranges
            if req.value(forHTTPHeaderField: "Range") == "bytes=0-0" {
                return (Self.resp(source, 200, ["Content-Length": "\(total)"]),
                        Data(repeating: 0xAB, count: total))
            }
            // single streaming GET
            return (Self.resp(source, 200, ["Content-Length": "\(total)"]),
                    Data(repeating: 0xAB, count: total))
        }
        defer { StubURLProtocol.handler = nil }

        let downloader = RangedDownloader(session: StubURLProtocol.session())
        var last: TransferProgress?
        for try await p in downloader.download(source, to: out, headers: [:],
                                               expectedSize: nil)
        {
            last = p
        }

        #expect(last?.bytesTransferred == Int64(total))
        #expect(last?.totalBytes == Int64(total)) // from Content-Length
        let written = try Data(contentsOf: out)
        #expect(written.count == total)
    }

    @Test func cancellationStopsTheStream() async throws {
        let total = 14 * 1024 * 1024
        let chunk = TransferProgress.chunkSize
        let out = dest()

        StubURLProtocol.handler = { req in
            if req.value(forHTTPHeaderField: "Range") == "bytes=0-0" {
                return (Self.resp(source, 206,
                                  ["Content-Range": "bytes 0-0/\(total)"]), Data(repeating: 0xAB, count: 1))
            }
            let parts = req.value(forHTTPHeaderField: "Range")!
                .dropFirst("bytes=".count).split(separator: "-")
            let start = Int(parts[0])!, end = Int(parts[1])!
            return (Self.resp(source, 206,
                              ["Content-Range": "bytes \(start)-\(end)/\(total)"]),
                    Data(repeating: 0xAB, count: end - start + 1))
        }
        defer { StubURLProtocol.handler = nil }

        let downloader = RangedDownloader(session: StubURLProtocol.session())
        let task = Task {
            var count = 0
            for try await _ in downloader.download(source, to: out, headers: [:],
                                                   expectedSize: Int64(total), chunkSize: chunk)
            {
                count += 1
                if count == 1 { break } // consumer stops early → onTermination cancels engine
            }
            return count
        }
        let seen = try await task.value
        #expect(seen == 1)
    }

    // MARK: - Helpers

    private static func resp(_ url: URL, _ code: Int, _ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func dest() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "dl-\(UUID().uuidString).bin")
    }

    // bytes 0xAB repeated; the engine writes whatever the stub returns.
    private func slice(_: Int, _: Int, _ count: Int) -> Data {
        Data(repeating: 0xAB, count: count)
    }
}
