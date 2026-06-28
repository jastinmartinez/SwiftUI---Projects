import Dependencies
import Foundation

struct MediaDownloadStoreClient: Sendable {
    typealias DownloadTarget = @Sendable (_ file: FileItem) async throws -> Target
    typealias WriteDownloadChunk = @Sendable (_ target: Target, _ data: Data, _ offset: UInt64) async throws -> Void

    var downloadTarget: DownloadTarget = { _ in throw Unimplemented() }
    var writeDownloadChunk: WriteDownloadChunk = { _, _, _ in throw Unimplemented() }
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
