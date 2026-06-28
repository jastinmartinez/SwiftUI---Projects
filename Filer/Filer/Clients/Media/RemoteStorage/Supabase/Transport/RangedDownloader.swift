import Foundation

/// Downloads a remote object using HTTP range requests when supported.
///
/// The downloader owns range probing, fallback choice, retry policy, response
/// validation, and progress emission. Persisted byte truth belongs to the sink.
struct RangedDownloader: Sendable {
    private let transport: HTTPTransport
    private let retryPolicy: TransferRetryPolicy

    init(
        transport: HTTPTransport,
        retryPolicy: TransferRetryPolicy
    ) {
        self.transport = transport
        self.retryPolicy = retryPolicy
    }

    func download(
        _ request: Request,
        sink: DownloadSink,
        chunkSize: Int = TransferProgress.chunkSize
    ) -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, sink, chunkSize, continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ download: Request,
        _ sink: DownloadSink,
        _ chunkSize: Int,
        _ continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws {
        try Task.checkCancellation()
        let probe = try await probe(download)
        let total = probe.totalLength ?? download.expectedSize ?? 0

        if probe.supportsRanges, total > 0 {
            try await rangedLoop(download, sink, UInt64(total), max(chunkSize, 1), continuation)
        } else {
            try await fallbackWholeBody(probe, expectedSize: download.expectedSize, sink, continuation)
        }
    }

    private func probe(_ download: Request) async throws -> ProbeResult {
        var retries = 0

        while true {
            try Task.checkCancellation()
            var probeRequest = request(url: download.url, headers: download.headers)
            probeRequest.httpMethod = "GET"
            probeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")

            do {
                let response = try await transport.data(probeRequest)
                return ProbeResult(response: response)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try recordRetry(for: error, retries: &retries)
            }
        }
    }

    private func rangedLoop(
        _ download: Request,
        _ sink: DownloadSink,
        _ total: UInt64,
        _ chunkSize: Int,
        _ continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws {
        let chunkSize = UInt64(chunkSize)
        let totalChunks = Int((total + chunkSize - 1) / chunkSize)
        var confirmedOffset = try await validatedOffset(sink, total: total)
        var retries = 0

        while confirmedOffset < total {
            try Task.checkCancellation()
            let start = confirmedOffset
            let end = min(start + chunkSize, total) - 1

            do {
                let body = try await rangeBody(download, start: start, end: end, expectedTotal: total)
                try await sink.write(body, start)
                confirmedOffset = try await validatedOffset(sink, total: total)
                retries = 0

                continuation.yield(
                    TransferProgress(
                        bytesTransferred: Int64(confirmedOffset),
                        totalBytes: Int64(total),
                        completedChunks: min(
                            completedChunks(for: confirmedOffset, chunkSize: chunkSize),
                            totalChunks
                        ),
                        totalChunks: totalChunks
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as Failure {
                throw failure
            } catch {
                try recordRetry(for: error, retries: &retries)
                confirmedOffset = try await validatedOffset(sink, total: total)
            }
        }
    }

    private func rangeBody(_ download: Request, start: UInt64, end: UInt64, expectedTotal: UInt64) async throws -> Data {
        var rangeRequest = request(url: download.url, headers: download.headers)
        rangeRequest.httpMethod = "GET"
        rangeRequest.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")

        let response = try await transport.data(rangeRequest)
        guard response.statusCode == 206 else {
            throw Failure.invalidRangeResponse
        }
        guard
            let contentRange = ContentRange.parse(response.value(forHeader: "Content-Range")),
            contentRange.start == start,
            contentRange.end == end,
            contentRange.total.map({ $0 == expectedTotal }) ?? true
        else {
            throw Failure.invalidRangeResponse
        }

        let expectedByteCount = Int(end - start + 1)
        guard response.body.count == expectedByteCount else {
            throw Failure.byteCountMismatch
        }

        return response.body
    }

    private func fallbackWholeBody(
        _ probe: ProbeResult,
        expectedSize: Int64?,
        _ sink: DownloadSink,
        _ continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws {
        guard probe.statusCode == 200 else {
            throw Failure.invalidFallbackResponse
        }

        let total = expectedSize ?? probe.totalLength ?? Int64(probe.body.count)
        var retries = 0

        while true {
            try Task.checkCancellation()
            guard try await sink.currentOffset() == 0 else {
                throw Failure.partialFallbackUnsupported
            }
            guard Int64(probe.body.count) == total else {
                throw Failure.byteCountMismatch
            }

            do {
                try await sink.write(probe.body, 0)
                let confirmedOffset = try await sink.currentOffset()
                continuation.yield(
                    TransferProgress(
                        bytesTransferred: Int64(confirmedOffset),
                        totalBytes: total > 0 ? total : Int64(confirmedOffset),
                        completedChunks: confirmedOffset > 0 ? 1 : 0,
                        totalChunks: 1
                    )
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as Failure {
                throw failure
            } catch {
                try recordRetry(for: error, retries: &retries)
            }
        }
    }

    private func validatedOffset(_ sink: DownloadSink, total: UInt64) async throws -> UInt64 {
        let offset = try await sink.currentOffset()
        guard offset <= total else {
            throw Failure.invalidResumeState
        }
        return offset
    }

    private func completedChunks(for offset: UInt64, chunkSize: UInt64) -> Int {
        guard offset > 0 else { return 0 }
        return Int((offset + chunkSize - 1) / chunkSize)
    }

    private func request(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func recordRetry(for error: Error, retries: inout Int) throws {
        guard retryPolicy.shouldRetry(error) else {
            throw error
        }
        guard retries < retryPolicy.maxRetries else {
            throw Failure.retryLimitExceeded
        }
        retries += 1
    }
}

private struct ContentRange: Equatable, Sendable {
    let start: UInt64
    let end: UInt64
    let total: UInt64?

    static func parse(_ value: String?) -> ContentRange? {
        guard let value else { return nil }

        let fields = value.split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, fields.first == "bytes" else { return nil }
        let rangeAndTotal = fields[1].split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard rangeAndTotal.count == 2 else { return nil }

        let bounds = rangeAndTotal[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
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

extension RangedDownloader {
    struct Request: Equatable, Sendable {
        let url: URL
        let headers: [String: String]
        let expectedSize: Int64?
    }

    /// Writes downloaded bytes and reports the confirmed persisted offset.
    ///
    /// The sink is the source of truth for resume. The downloader must not
    /// assume bytes are durable until the sink accepts them.
    struct DownloadSink: Sendable {
        typealias CurrentOffset = @Sendable () async throws -> UInt64
        typealias Write = @Sendable (_ data: Data, _ offset: UInt64) async throws -> Void

        var currentOffset: CurrentOffset
        var write: Write
    }

    struct ProbeResult: Equatable, Sendable {
        let statusCode: Int
        let supportsRanges: Bool
        let totalLength: Int64?
        let body: Data
    }

    enum Failure: Error, Equatable {
        case invalidRangeResponse
        case invalidFallbackResponse
        case byteCountMismatch
        case partialFallbackUnsupported
        case retryLimitExceeded
        case invalidResumeState
    }
}

extension RangedDownloader.ProbeResult {
    init(response: HTTPResponse) {
        statusCode = response.statusCode
        supportsRanges =
            response.statusCode == 206
                || response.value(forHeader: "Accept-Ranges")?.lowercased() == "bytes"
        if let contentRange = response.value(forHeader: "Content-Range") {
            totalLength = ContentRange.parse(contentRange)?.total.flatMap { Int64(exactly: $0) }
        } else {
            totalLength = response.value(forHeader: "Content-Length").flatMap(Int64.init)
        }
        body = response.body
    }
}
