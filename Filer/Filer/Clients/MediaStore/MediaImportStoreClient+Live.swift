import Dependencies
import Foundation

extension MediaImportStoreClient: DependencyKey {
    static let liveValue = live()

    static func live(
        contentStorage: MediaContentStorageClient = .liveValue,
        now: @escaping @Sendable () -> Date = Date.init,
        timeToLive: TimeInterval = defaultTimeToLive
    ) -> MediaImportStoreClient {
        let store: Store = { payload in
            let stored = try await contentStorage.storeImport(payload.metadata.id, payload.data)
            return ImportedMedia(
                metadata: payload.metadata.with(size: stored.size),
                fileURL: stored.localURL
            )
        }

        let removeExpired: RemoveExpired = {
            let expiredKeys = try await expiredKeys(
                in: contentStorage.listImports(),
                now: now(),
                timeToLive: timeToLive
            )
            for key in expiredKeys {
                try await contentStorage.removeImport(key)
            }
        }

        return MediaImportStoreClient(
            store: store,
            removeExpired: removeExpired
        )
    }
}
