import Dependencies
import Foundation

struct MediaRemoteStorageClient: Sendable {
    typealias List = @Sendable () async throws -> [FileItem]
    typealias Upload = @Sendable (_ media: ImportedMedia) -> AsyncThrowingStream<UploadEvent, Error>
    typealias Download = @Sendable (_ file: FileItem) -> AsyncThrowingStream<DownloadEvent, Error>

    var list: List
    var upload: Upload
    var download: Download

    init(
        list: @escaping List,
        upload: @escaping Upload,
        download: @escaping Download
    ) {
        self.list = list
        self.upload = upload
        self.download = download
    }
}

extension MediaRemoteStorageClient {
    enum UploadEvent: Equatable { case progress(TransferProgress), reconnecting, finished(FileItem) }
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
