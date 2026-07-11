import Dependencies
import Foundation

extension MediaDownloadClient: DependencyKey {
    static let liveValue = live()

    static func live(
        transport: HTTPTransport = .live(session: .shared),
        retryPolicy: MediaRemoteTransferPolicy = .default
    ) -> MediaDownloadClient {
        let engine = Engine(transport: transport, retryPolicy: retryPolicy)
        return MediaDownloadClient(run: { engine.run($0, $1) })
    }
}

private extension MediaDownloadClient {
    /// HTTP range-download engine. Owns the deps, range probing, fallback choice,
    /// retry policy, response validation, and progress emission.
    struct Engine: Sendable {
        typealias Request = MediaDownloadClient.Request
        typealias DownloadSink = MediaDownloadClient.DownloadSink
        typealias ProbeResult = MediaDownloadClient.ProbeResult
        typealias ContentRange = MediaDownloadClient.ContentRange
        typealias Failure = MediaDownloadClient.Failure

        let transport: HTTPTransport
        let retryPolicy: MediaRemoteTransferPolicy

        func run(_ request: Request, _ sink: DownloadSink) -> AsyncThrowingStream<
            TransferProgress, Error
        > {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await perform(request, sink, continuation)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }
}

private extension MediaDownloadClient.Engine {
    func perform(
        _ download: Request,
        _ sink: DownloadSink,
        _ continuation: AsyncThrowingStream<TransferProgress, Error>.Continuation
    ) async throws {
        try Task.checkCancellation()
        let probeResult = try await probe(download)
        let total = probeResult.totalLength ?? download.expectedSize ?? 0

        if probeResult.supportsRanges, total > 0 {
            try await downloadRanges(
                download,
                sink,
                UInt64(total),
                max(retryPolicy.chunkSize, 1),
                continuation
            )
        } else {
            try await downloadWholeResponse(
                probeResult,
                expectedSize: download.expectedSize,
                sink,
                continuation
            )
        }
    }

    func probe(_ downloadRequest: Request) async throws -> ProbeResult {
        var retries = 0

        while true {
            try Task.checkCancellation()
            var probeRequest = request(url: downloadRequest.url, headers: downloadRequest.headers)
            probeRequest.httpMethod = "GET"
            probeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")

            do {
                let response = try await transport.data(probeRequest)
                return ProbeResult(response: response)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                retries = try nextRetryCount(for: error, retries: retries)
            }
        }
    }

    func downloadRanges(
        _ downloadRequest: Request,
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
                let body = try await downloadRangeBody(
                    downloadRequest,
                    start: start,
                    end: end,
                    expectedTotal: total
                )
                try await sink.write(body, start)
                confirmedOffset = try await validatedOffset(sink, total: total)
                retries = 0

                continuation.yield(
                    TransferProgress(
                        bytesTransferred: Int64(confirmedOffset),
                        totalBytes: Int64(total),
                        completedChunks: min(
                            confirmedOffset > 0
                                ? Int((confirmedOffset + chunkSize - 1) / chunkSize) : 0,
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
                retries = try nextRetryCount(for: error, retries: retries)
                confirmedOffset = try await validatedOffset(sink, total: total)
            }
        }
    }

    func downloadRangeBody(
        _ downloadRequest: Request,
        start: UInt64,
        end: UInt64,
        expectedTotal: UInt64
    ) async throws -> Data {
        var rangeRequest = request(url: downloadRequest.url, headers: downloadRequest.headers)
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

    func downloadWholeResponse(
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
                retries = try nextRetryCount(for: error, retries: retries)
            }
        }
    }

    func validatedOffset(_ sink: DownloadSink, total: UInt64) async throws -> UInt64 {
        let offset = try await sink.currentOffset()
        guard offset <= total else {
            throw Failure.invalidResumeState
        }
        return offset
    }

    func request(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    func nextRetryCount(for error: Error, retries: Int) throws -> Int {
        guard retryPolicy.shouldRetry(error) else {
            throw error
        }
        guard retries < retryPolicy.maxRetries else {
            throw Failure.retryLimitExceeded
        }
        return retries + 1
    }
}
