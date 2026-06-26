@testable import Filer
import Foundation
import Testing

struct ImportedMediaTests {
    @Test func importedMediaIsIdentifiedByObjectPath() {
        let media = ImportedMedia(
            id: "abc.jpg", name: "Pic", fileURL: URL(fileURLWithPath: "/tmp/abc.jpg"),
            contentType: "image/jpeg", kind: .image, size: 2048
        )
        #expect(media.id == "abc.jpg")
        #expect(media.name == "Pic")
        #expect(media.contentType == "image/jpeg")
        #expect(media.kind == .image)
        #expect(media.size == 2048)
    }
}
