import Dependencies
import Foundation

/// The Supabase communication boundary: listing remote objects and building the
/// provider-specific upload/download requests. Transfer orchestration and caching
/// live in `MediaTransferClient`; this client owns only the remote
/// protocol details. The production implementation lives in `MediaRemoteClient+Live.swift`.
struct MediaRemoteClient: Sendable {
    typealias List = @Sendable () async throws -> [FileItem]
    typealias UploadRequestFor = @Sendable (_ media: ImportedMedia) -> UploadRequest
    typealias DownloadRequestFor = @Sendable (_ file: FileItem) throws -> DownloadRequest

    var list: List
    var uploadRequest: UploadRequestFor
    var downloadRequest: DownloadRequestFor
}

extension MediaRemoteClient {
    struct UploadRequest: Equatable, Sendable {
        let endpoint: URL
        /// Sent with every request in the upload (authentication).
        let commonHeaders: [String: String]
        /// Sent only with the create (POST): object metadata and upsert.
        let createHeaders: [String: String]
    }

    struct DownloadRequest: Equatable, Sendable {
        let url: URL
        let headers: [String: String]
    }
}

extension DependencyValues {
    var mediaRemote: MediaRemoteClient {
        get { self[MediaRemoteClient.self] }
        set { self[MediaRemoteClient.self] = newValue }
    }
}
