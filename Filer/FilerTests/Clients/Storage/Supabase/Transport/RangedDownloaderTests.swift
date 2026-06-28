@testable import Filer
import Foundation
import Testing

@Suite(.serialized) struct RangedDownloaderTests {
    @Test func rangedPathProbesAndWritesContiguously() async throws {
        let total = 14 * 1024 * 1024 // 6 + 6 + 2
        let chunk = TransferProgress.chunkSize
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
        let writer = MemoryDownloadWriter()
        var last: TransferProgress?
        for try await p in downloader.download(source, headers: [:],
                                               expectedSize: nil, chunkSize: chunk,
                                               write: writer.write)
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
        #expect(writer.data.count == total)
    }

    @Test func streamingFallbackUsesContentLength() async throws {
        let total = 5 * 1024 * 1024

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
        let writer = MemoryDownloadWriter()
        var last: TransferProgress?
        for try await p in downloader.download(source, headers: [:],
                                               expectedSize: nil,
                                               write: writer.write)
        {
            last = p
        }

        #expect(last?.bytesTransferred == Int64(total))
        #expect(last?.totalBytes == Int64(total)) // from Content-Length
        #expect(writer.data.count == total)
    }

    @Test func cancellationStopsTheStream() async throws {
        let total = 14 * 1024 * 1024
        let chunk = TransferProgress.chunkSize

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
        let writer = MemoryDownloadWriter()
        let task = Task {
            var count = 0
            for try await _ in downloader.download(source, headers: [:],
                                                   expectedSize: Int64(total), chunkSize: chunk,
                                                   write: writer.write)
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

    private var source: URL {
        URL(string: "https://example.supabase.co/object/public/bucket/file.bin")!
    }

    private static func resp(_ url: URL, _ code: Int, _ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    // bytes 0xAB repeated; the engine writes whatever the stub returns.
    private func slice(_: Int, _: Int, _ count: Int) -> Data {
        Data(repeating: 0xAB, count: count)
    }
}

// MARK: - Helpers

private final class MemoryDownloadWriter: @unchecked Sendable {
    private let box = LockedBox<Data>(Data())

    var data: Data { box.value }

    func write(_ data: Data, _ offset: UInt64) {
        box.mutate { stored in
            let offset = Int(offset)
            if stored.count < offset {
                stored.append(Data(repeating: 0, count: offset - stored.count))
            }
            if stored.count < offset + data.count {
                stored.append(Data(repeating: 0, count: offset + data.count - stored.count))
            }
            stored.replaceSubrange(offset ..< offset + data.count, with: data)
        }
    }
}
