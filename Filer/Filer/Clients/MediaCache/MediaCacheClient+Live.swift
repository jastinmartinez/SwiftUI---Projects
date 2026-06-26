import Dependencies
import Foundation

extension MediaCacheClient: DependencyKey {
    nonisolated static let liveValue = live()

    nonisolated static func live(
        objectStore: ObjectStoreClient = .live(),
        now: @escaping @Sendable () -> Date = Date.init,
        timeToLive: TimeInterval = defaultTimeToLive
    ) -> MediaCacheClient {
        MediaCacheClient(
            store: { payload in
                for id in try await expiredIDs(in: objectStore.list(), now: now(), timeToLive: timeToLive) {
                    try await objectStore.remove(id)
                }

                let stored = try await objectStore.put(ObjectStoreWrite(id: payload.id, data: payload.data))
                guard let fileURL = stored.fileURL else {
                    throw Failure.unsupportedStorageLocation
                }

                return ImportedMedia(
                    id: payload.id,
                    name: payload.name,
                    fileURL: fileURL,
                    contentType: payload.contentType,
                    kind: payload.kind,
                    size: stored.size
                )
            },
            removeExpired: {
                for id in try await expiredIDs(in: objectStore.list(), now: now(), timeToLive: timeToLive) {
                    try await objectStore.remove(id)
                }
            }
        )
    }
}
