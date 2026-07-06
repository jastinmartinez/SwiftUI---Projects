@testable import Filer
import Foundation
import Storage
import Testing

@Suite struct MediaRemoteClientAdapterTests {
    // MARK: FileItem(_ FileObject)

    @Test func fileObjectWithImageMetadataMapsToRemoteFileItem() throws {
        let object = FileObject(name: "abc.jpg", metadata: [
            "name": .string("Holiday Photo"),
            "mimetype": .string("image/jpeg"),
            "size": .double(2048),
        ])
        let item = try #require(FileItem(object))
        #expect(item.id == "abc.jpg")
        #expect(item.name == "Holiday Photo")
        #expect(item.contentType == "image/jpeg")
        #expect(item.kind == .image)
        #expect(item.size == 2048)
        #expect(item.status == .remote)
    }

    @Test func displayNameFallsBackToObjectKeyWhenAbsent() throws {
        let object = FileObject(name: "abc.jpg", metadata: ["mimetype": .string("image/jpeg"), "size": .double(2048)])
        let item = try #require(FileItem(object))
        #expect(item.name == "abc.jpg")
    }

    @Test func nonMediaObjectIsDroppedAsNil() {
        let object = FileObject(name: "notes.pdf", metadata: ["mimetype": .string("application/pdf"), "size": .double(10)])
        #expect(FileItem(object) == nil)
    }

    @Test func missingMimeMetadataIsDroppedAsNil() {
        let object = FileObject(name: "mystery.bin", metadata: ["size": .double(10)])
        #expect(FileItem(object) == nil)
    }

    // MARK: - Helpers
}
