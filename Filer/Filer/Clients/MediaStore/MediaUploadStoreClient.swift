import Dependencies
import Foundation

struct MediaUploadStoreClient: Sendable {
    typealias UploadSource = @Sendable (_ media: ImportedMedia) async throws -> Source

    var uploadSource: UploadSource = { _ in throw Unimplemented() }
}

extension MediaUploadStoreClient {
    struct Source: Equatable, Sendable {
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
