import Dependencies
import Foundation

extension MediaUploadStoreClient: DependencyKey {
    static let liveValue = live()

    static func live(
        contentStorage: MediaContentStorageClient = .liveValue
    ) -> MediaUploadStoreClient {
        let uploadSource: UploadSource = { media in
            let source = try await contentStorage.importUploadSource(media.id)
            let storedMedia = ImportedMedia(
                id: media.id,
                name: media.name,
                fileURL: source.localURL,
                contentType: media.contentType,
                kind: media.kind,
                size: source.size
            )
            return Source(media: storedMedia, localURL: source.localURL)
        }

        return MediaUploadStoreClient(uploadSource: uploadSource)
    }
}
