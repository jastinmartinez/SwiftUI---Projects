import Dependencies
import Foundation

struct MediaUploadStoreClient: Sendable {
    typealias LoadUploadSource = @Sendable (_ media: ImportedMedia) async throws -> UploadSource

    var loadUploadSource: LoadUploadSource

    init(loadUploadSource: @escaping LoadUploadSource) {
        self.loadUploadSource = loadUploadSource
    }
}

extension MediaUploadStoreClient {
    struct UploadSource: Equatable, Sendable {
        let media: ImportedMedia
        let localURL: URL
    }

    struct Unimplemented: Error {}
}

extension DependencyValues {
    var mediaUploadStore: MediaUploadStoreClient {
        get { self[MediaUploadStoreClient.self] }
        set { self[MediaUploadStoreClient.self] = newValue }
    }
}
