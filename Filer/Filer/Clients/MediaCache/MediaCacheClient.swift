import Foundation

struct MediaCacheClient: Sendable {
    var store: @Sendable (_ payload: MediaImportPayload) async throws -> ImportedMedia
    var removeExpired: @Sendable () async throws -> Void

    nonisolated init(
        store: @escaping @Sendable (_ payload: MediaImportPayload) async throws -> ImportedMedia = { _ in
            throw Unimplemented()
        },
        removeExpired: @escaping @Sendable () async throws -> Void = {
            throw Unimplemented()
        }
    ) {
        self.store = store
        self.removeExpired = removeExpired
    }
}

extension MediaCacheClient {
    struct Unimplemented: Error {}
}
