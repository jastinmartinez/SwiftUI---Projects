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
            let metadata = payload.metadata
            let stored = try await contentStorage.storeImport(metadata.id, payload.data)
            let kind: FileItem.Kind = switch metadata.kind {
            case .image: .image
            case .video: .video
            }
            return ImportedMedia(
                id: metadata.id,
                name: metadata.name,
                fileURL: stored.localURL,
                contentType: metadata.contentType,
                kind: kind,
                size: stored.size
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
