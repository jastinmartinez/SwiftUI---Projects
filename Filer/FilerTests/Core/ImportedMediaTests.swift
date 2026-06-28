@testable import Filer
import Foundation
import Testing

struct ImportedMediaTests {
    @Test func importedMediaIsIdentifiedByObjectPath() {
        let media = ImportedMedia(
            metadata: MediaMetadata(
                id: "abc.jpg",
                name: "Pic",
                contentType: "image/jpeg",
                kind: .image,
                size: 2048
            ),
            fileURL: URL(fileURLWithPath: "/tmp/abc.jpg")
        )
        #expect(media.id == "abc.jpg")
        #expect(media.name == "Pic")
        #expect(media.contentType == "image/jpeg")
        #expect(media.kind == .image)
        #expect(media.size == 2048)
    }

    @Test func sizeDefaultsToZeroWhenMetadataDoesNotHaveSize() {
        let media = ImportedMedia(
            metadata: MediaMetadata(
                id: "abc.jpg",
                name: "Pic",
                contentType: "image/jpeg",
                kind: .image,
                size: nil
            ),
            fileURL: URL(fileURLWithPath: "/tmp/abc.jpg")
        )

        #expect(media.size == 0)
    }
}
