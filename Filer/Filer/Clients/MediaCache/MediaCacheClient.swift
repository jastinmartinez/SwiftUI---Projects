import Dependencies
import Foundation

struct MediaCacheClient: Sendable {
    var store: @Sendable (_ payload: MediaImportPayload) async throws -> ImportedMedia = { _ in
        throw Unimplemented()
    }

    var removeExpired: @Sendable () async throws -> Void = {
        throw Unimplemented()
    }
}

extension MediaCacheClient {
    struct Unimplemented: Error {}
}

extension DependencyValues {
    var mediaCache: MediaCacheClient {
        get { self[MediaCacheClient.self] }
        set { self[MediaCacheClient.self] = newValue }
    }
}
