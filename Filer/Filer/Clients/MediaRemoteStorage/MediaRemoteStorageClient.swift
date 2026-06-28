import Dependencies
import Foundation

struct MediaRemoteStorageClient: Sendable {
    typealias List = @Sendable () async throws -> [FileItem]
    typealias Upload = @Sendable (_ media: ImportedMedia) -> AsyncThrowingStream<UploadEvent, Error>
    typealias Download = @Sendable (_ file: FileItem) -> AsyncThrowingStream<DownloadEvent, Error>

    var list: List = { throw Unimplemented("mediaRemoteStorage.list") }
    var upload: Upload = { _ in AsyncThrowingStream { $0.finish(throwing: Unimplemented("mediaRemoteStorage.upload")) } }
    var download: Download = { _ in AsyncThrowingStream { $0.finish(throwing: Unimplemented("mediaRemoteStorage.download")) } }
}

extension MediaRemoteStorageClient {
    enum UploadEvent: Equatable { case progress(TransferProgress), finished(FileItem) }
    enum DownloadEvent: Equatable { case progress(TransferProgress), finished(URL) }

    struct Unimplemented: Error {
        let endpoint: String
        init(_ endpoint: String) { self.endpoint = endpoint }
    }
}

extension DependencyValues {
    var mediaRemoteStorage: MediaRemoteStorageClient {
        get { self[MediaRemoteStorageClient.self] }
        set { self[MediaRemoteStorageClient.self] = newValue }
    }
}
