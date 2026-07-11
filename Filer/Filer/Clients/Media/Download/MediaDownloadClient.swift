import Dependencies
import Foundation

/// Downloads a remote object using HTTP range requests when supported.
///
/// The downloader owns range probing, fallback choice, retry policy, response
/// validation, and progress emission. Persisted byte truth belongs to the sink.
/// The production implementation lives in `MediaDownloadClient+Live.swift`.
struct MediaDownloadClient: Sendable {
    typealias Run = @Sendable (_ request: Request, _ sink: DownloadSink) -> AsyncThrowingStream<TransferProgress, Error>

    var run: Run
}

extension MediaDownloadClient {
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

extension DependencyValues {
    var mediaDownload: MediaDownloadClient {
        get { self[MediaDownloadClient.self] }
        set { self[MediaDownloadClient.self] = newValue }
    }
}
