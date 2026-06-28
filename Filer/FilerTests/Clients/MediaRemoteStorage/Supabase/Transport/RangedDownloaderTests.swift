@testable import Filer
import Foundation
import Testing

@Suite(.serialized) struct RangedDownloaderTests {
    @Test func rangedPathProbesAndWritesContiguously() async throws {
        let url = try source()
        let total = 14 * 1024 * 1024
        let chunk = TransferProgress.chunkSize
        let body = Data(repeating: 0xAB, count: total)
        let requests = LockedBox<[URLRequest]>([])
        let sink = MemoryDownloadSink()

        let transport = HTTPTransport(
            data: { request in
                requests.mutate { $0.append(request) }
                let range = request.value(forHTTPHeaderField: "Range")
                if range == "bytes=0-0" {
                    return HTTPResponse(
                        statusCode: 206,
                        headers: [
                            "Content-Range": "bytes 0-0/\(total)",
                            "Accept-Ranges": "bytes",
                        ],
                        body: Data([0xAB])
                    )
                }

                let bounds = try Self.rangeBounds(range)
                let count = bounds.end - bounds.start + 1
                return try HTTPResponse(
                    statusCode: 206,
                    headers: ["Content-Range": "bytes \(bounds.start)-\(bounds.end)/\(total)"],
                    body: Self.slice(body, start: bounds.start, count: count)
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        var progress: [TransferProgress] = []
        for try await update in downloader.download(
            RangedDownloader.Request(
                url: url,
                headers: ["Authorization": "Bearer token"],
                expectedSize: nil
            ),
            sink: sink.sink,
            chunkSize: chunk
        ) {
            progress.append(update)
        }

        let ranges = requests.value.map { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges == [
            "bytes=0-0",
            "bytes=0-\(chunk - 1)",
            "bytes=\(chunk)-\(2 * chunk - 1)",
            "bytes=\(2 * chunk)-\(total - 1)",
        ])
        #expect(requests.value.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token" })
        #expect(sink.data == body)

        let last = try #require(progress.last)
        #expect(last.bytesTransferred == Int64(total))
        #expect(last.totalBytes == Int64(total))
        #expect(last.completedChunks == 3)
        #expect(last.totalChunks == 3)
    }

    @Test func resumesFromConfirmedSinkOffsetAfterTransientFailure() async throws {
        let url = try source()
        let total = 12 * 1024 * 1024
        let chunk = TransferProgress.chunkSize
        let body = Data(repeating: 0xCD, count: total)
        let requests = LockedBox<[URLRequest]>([])
        let failedSecondChunk = LockedBox(false)
        let sink = MemoryDownloadSink()

        let transport = HTTPTransport(
            data: { request in
                requests.mutate { $0.append(request) }
                let range = request.value(forHTTPHeaderField: "Range")
                if range == "bytes=0-0" {
                    return HTTPResponse(
                        statusCode: 206,
                        headers: [
                            "Content-Range": "bytes 0-0/\(total)",
                            "Accept-Ranges": "bytes",
                        ],
                        body: Data([0xCD])
                    )
                }

                let bounds = try Self.rangeBounds(range)
                if bounds.start == chunk, failedSecondChunk.value == false {
                    failedSecondChunk.mutate { $0 = true }
                    throw URLError(.networkConnectionLost)
                }

                let count = bounds.end - bounds.start + 1
                return try HTTPResponse(
                    statusCode: 206,
                    headers: ["Content-Range": "bytes \(bounds.start)-\(bounds.end)/\(total)"],
                    body: Self.slice(body, start: bounds.start, count: count)
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        for try await _ in downloader.download(
            RangedDownloader.Request(url: url, headers: [:], expectedSize: nil),
            sink: sink.sink,
            chunkSize: chunk
        ) {}

        let ranges = requests.value.map { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges == [
            "bytes=0-0",
            "bytes=0-\(chunk - 1)",
            "bytes=\(chunk)-\(2 * chunk - 1)",
            "bytes=\(chunk)-\(2 * chunk - 1)",
        ])
        #expect(sink.data == body)
    }

    @Test func fallbackIsRejectedWhenPartialBytesExist() async throws {
        let url = try source()
        let sink = MemoryDownloadSink(initialData: Data([0x01, 0x02]))
        let transport = HTTPTransport(
            data: { _ in
                HTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Length": "3"],
                    body: Data([0x01, 0x02, 0x03])
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        await #expect(throws: RangedDownloader.Failure.partialFallbackUnsupported) {
            for try await _ in downloader.download(
                RangedDownloader.Request(url: url, headers: [:], expectedSize: nil),
                sink: sink.sink
            ) {}
        }
    }

    @Test func invalidFallbackResponseDoesNotWrite() async throws {
        let url = try source()
        let requests = LockedBox<[URLRequest]>([])
        let sink = MemoryDownloadSink()
        let transport = HTTPTransport(
            data: { request in
                requests.mutate { $0.append(request) }
                return HTTPResponse(
                    statusCode: 404,
                    headers: ["Content-Length": "9"],
                    body: Data("not found".utf8)
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        await #expect(throws: RangedDownloader.Failure.invalidFallbackResponse) {
            for try await _ in downloader.download(
                RangedDownloader.Request(url: url, headers: [:], expectedSize: nil),
                sink: sink.sink
            ) {}
        }

        #expect(requests.value.count == 1)
        #expect(sink.data.isEmpty)
    }

    @Test func fallbackExpectedSizeMismatchFailsBeforeWritingOrRetrying() async throws {
        let url = try source()
        let requests = LockedBox<[URLRequest]>([])
        let sink = MemoryDownloadSink()
        let transport = HTTPTransport(
            data: { request in
                requests.mutate { $0.append(request) }
                return HTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Length": "3"],
                    body: Data([0x01, 0x02, 0x03])
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        await #expect(throws: RangedDownloader.Failure.byteCountMismatch) {
            for try await _ in downloader.download(
                RangedDownloader.Request(url: url, headers: [:], expectedSize: 4),
                sink: sink.sink
            ) {}
        }

        #expect(requests.value.count == 1)
        #expect(sink.data.isEmpty)
    }

    @Test func fallbackContentLengthMismatchFailsBeforeWritingOrRetrying() async throws {
        let url = try source()
        let requests = LockedBox<[URLRequest]>([])
        let sink = MemoryDownloadSink()
        let transport = HTTPTransport(
            data: { request in
                requests.mutate { $0.append(request) }
                return HTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Length": "4"],
                    body: Data([0x01, 0x02, 0x03])
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        await #expect(throws: RangedDownloader.Failure.byteCountMismatch) {
            for try await _ in downloader.download(
                RangedDownloader.Request(url: url, headers: [:], expectedSize: nil),
                sink: sink.sink
            ) {}
        }

        #expect(requests.value.count == 1)
        #expect(sink.data.isEmpty)
    }

    @Test func invalidRangeByteCountFails() async throws {
        let url = try source()
        let total = TransferProgress.chunkSize
        let requests = LockedBox<[URLRequest]>([])
        let sink = MemoryDownloadSink()
        let transport = HTTPTransport(
            data: { request in
                requests.mutate { $0.append(request) }
                let range = request.value(forHTTPHeaderField: "Range")
                if range == "bytes=0-0" {
                    return HTTPResponse(
                        statusCode: 206,
                        headers: [
                            "Content-Range": "bytes 0-0/\(total)",
                            "Accept-Ranges": "bytes",
                        ],
                        body: Data([0xEF])
                    )
                }

                return HTTPResponse(
                    statusCode: 206,
                    headers: ["Content-Range": "bytes 0-\(total - 1)/\(total)"],
                    body: Data(repeating: 0xEF, count: total - 1)
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        await #expect(throws: RangedDownloader.Failure.byteCountMismatch) {
            for try await _ in downloader.download(
                RangedDownloader.Request(url: url, headers: [:], expectedSize: nil),
                sink: sink.sink,
                chunkSize: total
            ) {}
        }

        let ranges = requests.value.map { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges == [
            "bytes=0-0",
            "bytes=0-\(total - 1)",
        ])
    }

    @Test func unknownProbeTotalUsesExpectedSizeInsteadOfProbeBodyLength() async throws {
        let url = try source()
        let total = 4
        let body = Data([0x01, 0x02, 0x03, 0x04])
        let requests = LockedBox<[URLRequest]>([])
        let sink = MemoryDownloadSink()
        let transport = HTTPTransport(
            data: { request in
                requests.mutate { $0.append(request) }
                let range = request.value(forHTTPHeaderField: "Range")
                if range == "bytes=0-0" {
                    return HTTPResponse(
                        statusCode: 206,
                        headers: [
                            "Content-Range": "bytes 0-0/*",
                            "Content-Length": "1",
                        ],
                        body: Data([0x01])
                    )
                }

                let bounds = try Self.rangeBounds(range)
                let count = bounds.end - bounds.start + 1
                return try HTTPResponse(
                    statusCode: 206,
                    headers: ["Content-Range": "bytes \(bounds.start)-\(bounds.end)/\(total)"],
                    body: Self.slice(body, start: bounds.start, count: count)
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        for try await _ in downloader.download(
            RangedDownloader.Request(url: url, headers: [:], expectedSize: Int64(total)),
            sink: sink.sink,
            chunkSize: total
        ) {}

        let ranges = requests.value.map { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges == [
            "bytes=0-0",
            "bytes=0-\(total - 1)",
        ])
        #expect(sink.data.count == total)
        #expect(sink.data == body)
    }

    @Test func mismatchedContentRangeFailsWithoutWritingOrRetrying() async throws {
        let url = try source()
        let total = TransferProgress.chunkSize
        let requests = LockedBox<[URLRequest]>([])
        let sink = MemoryDownloadSink()
        let transport = HTTPTransport(
            data: { request in
                requests.mutate { $0.append(request) }
                let range = request.value(forHTTPHeaderField: "Range")
                if range == "bytes=0-0" {
                    return HTTPResponse(
                        statusCode: 206,
                        headers: [
                            "Content-Range": "bytes 0-0/\(total)",
                            "Accept-Ranges": "bytes",
                        ],
                        body: Data([0xF0])
                    )
                }

                return HTTPResponse(
                    statusCode: 206,
                    headers: ["Content-Range": "bytes 1-\(total)/\(total)"],
                    body: Data(repeating: 0xF0, count: total)
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        await #expect(throws: RangedDownloader.Failure.invalidRangeResponse) {
            for try await _ in downloader.download(
                RangedDownloader.Request(url: url, headers: [:], expectedSize: nil),
                sink: sink.sink,
                chunkSize: total
            ) {}
        }

        let ranges = requests.value.map { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges == [
            "bytes=0-0",
            "bytes=0-\(total - 1)",
        ])
        #expect(sink.data.isEmpty)
    }

    @Test func wrongRangeTotalFailsWithoutWritingOrRetrying() async throws {
        let url = try source()
        let total = 4
        let requests = LockedBox<[URLRequest]>([])
        let sink = MemoryDownloadSink()
        let transport = HTTPTransport(
            data: { request in
                requests.mutate { $0.append(request) }
                let range = request.value(forHTTPHeaderField: "Range")
                if range == "bytes=0-0" {
                    return HTTPResponse(
                        statusCode: 206,
                        headers: [
                            "Content-Range": "bytes 0-0/\(total)",
                            "Accept-Ranges": "bytes",
                        ],
                        body: Data([0xF1])
                    )
                }

                return HTTPResponse(
                    statusCode: 206,
                    headers: ["Content-Range": "bytes 0-\(total - 1)/\(total + 1)"],
                    body: Data(repeating: 0xF1, count: total)
                )
            },
            upload: { _, _ in HTTPResponse(statusCode: 204, headers: [:], body: Data()) }
        )

        let downloader = RangedDownloader(transport: transport)
        await #expect(throws: RangedDownloader.Failure.invalidRangeResponse) {
            for try await _ in downloader.download(
                RangedDownloader.Request(url: url, headers: [:], expectedSize: nil),
                sink: sink.sink,
                chunkSize: total
            ) {}
        }

        let ranges = requests.value.map { $0.value(forHTTPHeaderField: "Range") }
        #expect(ranges == [
            "bytes=0-0",
            "bytes=0-\(total - 1)",
        ])
        #expect(sink.data.isEmpty)
    }

    private func source() throws -> URL {
        try #require(URL(string: "https://example.supabase.co/object/authenticated/bucket/file.bin"))
    }

    private static func rangeBounds(_ value: String?) throws -> (start: Int, end: Int) {
        let value = value ?? "bytes=0-0"
        let parts = value.dropFirst("bytes=".count).split(separator: "-")
        let startText = try #require(parts.first)
        let endText = try #require(parts.dropFirst().first)
        let start = try #require(Int(startText))
        let end = try #require(Int(endText))
        return (start, end)
    }

    private static func slice(_ body: Data, start: Int, count: Int) throws -> Data {
        let end = start + count
        try #require(start >= 0)
        try #require(count >= 0)
        try #require(end <= body.count)
        return body.subdata(in: start ..< end)
    }
}

// MARK: - Helpers

private final class MemoryDownloadSink: @unchecked Sendable {
    private let box: LockedBox<Data>

    init(initialData: Data = Data()) {
        box = LockedBox(initialData)
    }

    var data: Data { box.value }

    var sink: RangedDownloader.DownloadSink {
        RangedDownloader.DownloadSink(
            currentOffset: { UInt64(self.box.value.count) },
            write: { data, offset in
                self.box.mutate { stored in
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
        )
    }
}
