import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct StorageClient {
    var list: () async throws -> [FileItem]
    var upload: (_ media: ImportedMedia) -> AsyncThrowingStream<UploadEvent, Error> = { _ in AsyncThrowingStream { $0.finish() } }
    var download: (_ file: FileItem) -> AsyncThrowingStream<DownloadEvent, Error> = { _ in AsyncThrowingStream { $0.finish() } }
}

extension StorageClient {
    enum UploadEvent: Equatable { case progress(TransferProgress), finished(FileItem) }
    enum DownloadEvent: Equatable { case progress(TransferProgress), finished(URL) }
}

extension DependencyValues {
    var storage: StorageClient {
        get { self[StorageClient.self] }
        set { self[StorageClient.self] = newValue }
    }
}
