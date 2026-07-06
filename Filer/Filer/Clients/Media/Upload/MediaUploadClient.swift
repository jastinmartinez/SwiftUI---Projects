import Dependencies
import Foundation

/// TUS-resumable upload client. Generic HTTP machinery: no Supabase, no TCA.
/// The production implementation lives in `MediaUploadClient+Live.swift`.
struct MediaUploadClient: Sendable {
    typealias Run = @Sendable (_ request: Request, _ source: UploadSource) -> AsyncThrowingStream<Event, Error>

    var run: Run
}

extension MediaUploadClient {
    enum Event: Equatable {
        case progress(TransferProgress)
        case waitingForConnectivity
    }

    struct Request: Equatable, Sendable {
        let endpoint: URL
        /// Sent with every request in the upload (e.g. authentication).
        let commonHeaders: [String: String]
        /// Sent only with the create (POST) request.
        let createHeaders: [String: String]
    }

    struct UploadSource: Sendable {
        typealias Read = @Sendable (_ offset: Int, _ length: Int) async throws -> Data

        let size: Int
        // `read` is a stored field, not a `run` parameter: a streaming upload needs it to
        // outlive `run` (the async task reads chunks later), and only struct-stored closures
        // are escaping in Swift — a bare closure parameter can't be captured by the task.
        let read: Read
    }

    enum Failure: Error, Equatable {
        case invalidUploadSource
        case invalidCreateResponse
        case invalidPatchResponse
        case invalidResumeResponse
        case uploadConflict
    }
}

extension DependencyValues {
    var mediaUpload: MediaUploadClient {
        get { self[MediaUploadClient.self] }
        set { self[MediaUploadClient.self] = newValue }
    }
}
