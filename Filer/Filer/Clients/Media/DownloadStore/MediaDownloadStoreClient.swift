import Dependencies
import Foundation

struct MediaDownloadStoreClient: Sendable {
    typealias DownloadTarget = @Sendable (_ file: FileItem) async throws -> Target
    typealias DownloadSink = @Sendable (_ target: Target) -> RangedDownloader.DownloadSink
    typealias WriteDownloadChunk = @Sendable (_ target: Target, _ data: Data, _ offset: UInt64) async throws -> Void

    var downloadTarget: DownloadTarget
    var downloadSink: DownloadSink
    var writeDownloadChunk: WriteDownloadChunk

    init(
        downloadTarget: @escaping DownloadTarget,
        downloadSink: @escaping DownloadSink,
        writeDownloadChunk: @escaping WriteDownloadChunk
    ) {
        self.downloadTarget = downloadTarget
        self.downloadSink = downloadSink
        self.writeDownloadChunk = writeDownloadChunk
    }
}

extension MediaDownloadStoreClient {
    struct Target: Equatable, Sendable {
        let file: FileItem
        let key: String
        let localURL: URL
    }

    struct Unimplemented: Error {}
}

extension DependencyValues {
    var mediaDownloadStore: MediaDownloadStoreClient {
        get { self[MediaDownloadStoreClient.self] }
        set { self[MediaDownloadStoreClient.self] = newValue }
    }
}
