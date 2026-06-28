import Dependencies
import Foundation

extension MediaUploadStoreClient: DependencyKey {
    static let liveValue = live()

    static func live(
        contentStorage: MediaContentStorageClient = .liveValue
    ) -> MediaUploadStoreClient {
        let uploadSource: UploadSource = { media in
            let source = try await contentStorage.importUploadSource(media.metadata.id)
            let storedMedia = ImportedMedia(
                metadata: media.metadata.with(size: source.size),
                fileURL: source.localURL
            )
            return Source(media: storedMedia, localURL: source.localURL)
        }

        return MediaUploadStoreClient(uploadSource: uploadSource)
    }
}
