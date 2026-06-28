@testable import Filer
import Foundation
import Testing

@Suite struct MediaUploadStoreClientTests {
    @Test func uploadSourceResolvesStoredImportForMediaID() async throws {
        let requestedKeys = LockedBox<[String]>([])
        let contentStorage = Self.contentStorage(
            importUploadSource: { key in
                requestedKeys.mutate { $0.append(key) }
                return MediaContentStorageClient.UploadSource(
                    key: key,
                    localURL: URL(fileURLWithPath: "/memory/imports/\(key)"),
                    size: 12
                )
            }
        )
        let client = MediaUploadStoreClient.live(contentStorage: contentStorage)

        let source = try await client.uploadSource(media())

        #expect(requestedKeys.value == ["abc.jpg"])
        #expect(source.localURL == URL(fileURLWithPath: "/memory/imports/abc.jpg"))
        #expect(source.media.fileURL == URL(fileURLWithPath: "/memory/imports/abc.jpg"))
        #expect(source.media.size == 12)
        #expect(source.media.name == "Photo")
    }

    @Test func uploadSourcePropagatesMissingContent() async {
        let contentStorage = Self.contentStorage(
            importUploadSource: { key in throw MediaContentStorageClient.MissingContent(key: key) }
        )
        let client = MediaUploadStoreClient.live(contentStorage: contentStorage)

        do {
            _ = try await client.uploadSource(media())
            Issue.record("Expected missing content error")
        } catch {
            #expect(error as? MediaContentStorageClient.MissingContent == .init(key: "abc.jpg"))
        }
    }

    // MARK: - Helpers

    private func media() -> ImportedMedia {
        ImportedMedia(
            metadata: MediaMetadata(
                id: "abc.jpg",
                name: "Photo",
                contentType: "image/jpeg",
                kind: .image,
                size: 1
            ),
            fileURL: URL(fileURLWithPath: "/tmp/abc.jpg")
        )
    }

    private static func contentStorage(
        importUploadSource: @escaping MediaContentStorageClient.ImportUploadSource
    ) -> MediaContentStorageClient {
        MediaContentStorageClient(
            storeImport: { _, _ in throw MediaContentStorageClient.Unimplemented() },
            listImports: { throw MediaContentStorageClient.Unimplemented() },
            removeImport: { _ in throw MediaContentStorageClient.Unimplemented() },
            importUploadSource: importUploadSource,
            prepareDownloadTarget: { _ in throw MediaContentStorageClient.Unimplemented() },
            downloadOffset: { _ in throw MediaContentStorageClient.Unimplemented() },
            writeDownload: { _, _, _ in throw MediaContentStorageClient.Unimplemented() }
        )
    }
}
