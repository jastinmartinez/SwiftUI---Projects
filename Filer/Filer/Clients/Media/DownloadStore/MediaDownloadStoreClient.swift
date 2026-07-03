import Dependencies
import Foundation

struct MediaDownloadStoreClient: Sendable {
    typealias PrepareDownloadTarget = @Sendable (_ file: FileItem) async throws -> DownloadTarget
    typealias MakeDownloadSink = @Sendable (_ target: DownloadTarget) -> RangedDownloader.DownloadSink

    var prepareDownloadTarget: PrepareDownloadTarget
    var makeDownloadSink: MakeDownloadSink

    init(
        prepareDownloadTarget: @escaping PrepareDownloadTarget,
        makeDownloadSink: @escaping MakeDownloadSink
    ) {
        self.prepareDownloadTarget = prepareDownloadTarget
        self.makeDownloadSink = makeDownloadSink
    }
}

extension MediaDownloadStoreClient {
    struct DownloadTarget: Equatable, Sendable {
        let file: FileItem
        let key: String
        let localURL: URL
    }
}

extension DependencyValues {
    var mediaDownloadStore: MediaDownloadStoreClient {
        get { self[MediaDownloadStoreClient.self] }
        set { self[MediaDownloadStoreClient.self] = newValue }
    }
}
