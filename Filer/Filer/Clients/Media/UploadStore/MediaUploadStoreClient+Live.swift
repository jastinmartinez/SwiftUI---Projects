import Dependencies
import Foundation

extension MediaUploadStoreClient: DependencyKey {
    static let liveValue = live(contentStorage: .liveValue)

    static func live(
        contentStorage: MediaContentStorageClient
    ) -> MediaUploadStoreClient {
        let loadUploadSource: LoadUploadSource = { media in
            let source = try await contentStorage.importUploadSource(media.metadata.id)
            let storedMedia = ImportedMedia(
                metadata: media.metadata.with(size: source.size),
                fileURL: source.localURL
            )
            return UploadSource(media: storedMedia, localURL: source.localURL)
        }

        return MediaUploadStoreClient(loadUploadSource: loadUploadSource)
    }
}
