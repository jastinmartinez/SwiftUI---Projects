@testable import Filer
import Testing

struct MediaMetadataTests {
    @Test func withSizeReturnsCopyWithUpdatedSize() {
        let metadata = MediaMetadata(
            id: "abc.jpg",
            name: "Photo",
            contentType: "image/jpeg",
            kind: .image,
            size: nil
        )

        let updated = metadata.with(size: 12)

        #expect(updated.id == "abc.jpg")
        #expect(updated.name == "Photo")
        #expect(updated.contentType == "image/jpeg")
        #expect(updated.kind == .image)
        #expect(updated.size == 12)
    }
}
